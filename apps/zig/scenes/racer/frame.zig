// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; his itch.io page states "Code license: MIT"), re-written in Zig integers.
// Copyright (c) freds72, MIT. The MIT licence:
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
//   associated documentation files (the "Software"), to deal in the Software without restriction,
//   including without limitation the rights to use, copy, modify, merge, publish, distribute,
//   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions: the above copyright notice and this
//   permission notice shall be included in all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
//   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
//   OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// RACER: one frame's geometry, as the four stages the benchmark times (each a `noinline` fn so
// apps/harness/frame_cost.mjs bills it by name):
//
//   visibility  the PVS list of tiles for the camera's tile and yaw bucket, cut at R (pvs.zig)
//   collect     per tile, per face not yet seen this frame: back-face test (dual-sided skips it),
//               transform the vertices through the cache, trivial reject by outcode, clip if a vertex
//               is past the near plane or the guard band, project, depth key. A face's decals (its
//               inner faces) follow it with the same key, never sorted alone
//   sort        a counting sort on the key: 1,024 buckets of 1/8 unit, far to near, stable (a
//               decal stays after its parent)
//   emit        far to near through poly.Emitter into a Sink (CPU spans or AFFINE records)
// Cars and skidmarks join the same sort (M2, project.zig): one list, so a crest hides a car behind it.
// No ZigOS import: the Sink is a parameter.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const fx = @import("fx.zig");
const poly = @import("poly.zig");
const project = @import("project.zig");
const oracle = @import("oracle.zig");
const pvs = @import("pvs.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");
const facing = types.facing;
const offScreen = types.offScreen;
const xf = @import("xform.zig");

pub const BUCKETS = 1024;
pub const TALL: i32 = 128; // Q7: a face this tall (1 unit) or taller is drawn in the far ring
pub var ring: u32 = 0; // key +: the far ring's depth past R, in tiles (0 = off, the default)

fn tall(t: *const trk.Track, f: *const trk.Face) bool {
    var lo: i32 = t.verts[f.v[0]][1];
    var hi: i32 = lo;
    for (f.v[1..f.nv]) |id| {
        lo = @min(lo, t.verts[id][1]);
        hi = @max(hi, t.verts[id][1]);
    }
    return hi - lo >= TALL;
}
pub const MAXP = 6144; // polygons kept a frame (the stress city at R = 8 stays under it); past it they are dropped, counted
pub const MAXV = types.MAXV;
const NO_KEY: u16 = 0xFFFF;
pub const Rec = types.Rec;
pub const Stats = types.Stats;

pub const Frame = struct {
    cache: xf.Cache,
    kept: []Rec, // MAXP
    key: []u16, // MAXP
    order: []u16, // MAXP, far to near
    count: *[BUCKETS + 1]u32,
    seen: []u32, // a face's frame stamp
    fkey: []u16 = &.{}, // the key a face was kept with (read through faceKey: valid when seen == the stamp)
    seen_stamp: u32 = 0,
    entries: [pvs.MAX_ENTRIES]u16 = undefined,
    pvs_entries: [pvs.MAX_ENTRIES]u16 = undefined, // the oracle's (key 2) PVS list beside its all-tiles one
    pvs_list: []const u16 = &.{},
    list: []const u16 = &.{},
    stats: Stats = .{},

    pub noinline fn visibility(self: *Frame, t: *const trk.Track, v: *const cam.View, r: u32) void {
        self.list = pvs.visible(t, v.tile, v.bucket, r, &self.entries);
        if (oracle.all_tiles) { // the bug pass' oracle (oracle.zig): every tile within R, the PVS kept aside
            self.pvs_list = pvs.visible(t, v.tile, v.bucket, r, &self.pvs_entries);
            self.list = oracle.allTiles(t, v, r, self.pvs_list, &self.entries);
        }
        self.stats = .{ .tiles = @intCast(self.list.len) };
    }

    pub noinline fn collect(self: *Frame, t: *const trk.Track, v: *const cam.View, decals: bool) void {
        self.cache.next();
        self.seen_stamp +%= 1;
        if (self.seen_stamp == 0) {
            @memset(self.seen, 0);
            self.seen_stamp = 1;
        }
        @memset(self.count, 0);
        for (self.list) |e| {
            for (t.tileFaces(pvs.tileOf(e))) |fid| {
                if (self.seen[fid] == self.seen_stamp) continue;
                self.seen[fid] = self.seen_stamp;
                if (self.fkey.len != 0) self.fkey[fid] = NO_KEY;
                self.stats.faces += 1;
                const f = &t.faces[fid];
                if (f.flags & trk.FLAG_DUAL == 0 and facing(f, v) <= f.cp) {
                    self.stats.back += 1;
                    continue;
                }
                self.face(t, v, fid, decals);
            }
        }
        self.stats.verts = self.cache.touched;
    }

    /// The far ring (R82 bug pass, item 7; key +, `ring` tiles past R): from the tiles the run-time DDA reaches between R
    /// and R + ring steps, only the TALL faces (a vertical extent of at least TALL: trees, buildings, hills, walls), never
    /// the flat ground, which the far ground's colour already stands in for. Things on the horizon rise in earlier
    /// instead of popping in at R; the cost is those faces only. After collect, before the cars.
    pub noinline fn far(self: *Frame, t: *const trk.Track, v: *const cam.View, r: u32, extra: u32) void {
        if (extra == 0) return;
        var scratch: [pvs.MAX_ENTRIES]u16 = undefined;
        const n = pvs.dda(t, v.tile, v.bucket, r + extra, &scratch);
        for (scratch[0..n]) |e| {
            if (pvs.distOf(e) <= r) break; // far to near: the rest is the PVS' own
            for (t.tileFaces(pvs.tileOf(e))) |fid| {
                if (self.seen[fid] == self.seen_stamp or !tall(t, &t.faces[fid])) continue;
                self.seen[fid] = self.seen_stamp;
                if (self.fkey.len != 0) self.fkey[fid] = NO_KEY;
                const f = &t.faces[fid];
                if (f.flags & trk.FLAG_DUAL == 0 and facing(f, v) <= f.cp) continue;
                self.face(t, v, fid, false);
            }
        }
    }

    pub noinline fn sort(self: *Frame) void {
        const n = self.stats.polys;
        for (1..BUCKETS + 1) |k| self.count[k] += self.count[k - 1];
        for (self.key[0..n], 0..) |k, i| {
            self.order[self.count[k]] = @intCast(i);
            self.count[k] += 1;
        }
    }

    pub noinline fn emit(self: *Frame, comptime Sink: type, em: *poly.Emitter(Sink)) void {
        var xs: [MAXV]i32 = undefined;
        var ys: [MAXV]i32 = undefined;
        for (self.order[0..self.stats.polys]) |i| {
            const r = &self.kept[i];
            const n = r.n & types.COUNT;
            for (0..n) |j| {
                xs[j] = r.x[j];
                ys[j] = r.y[j];
            }
            if (r.n & types.SHADOW != 0) em.shadow(xs[0..n], ys[0..n]) else if (r.n & types.LIGHT != 0) em.light(xs[0..n], ys[0..n]) else em.poly(xs[0..n], ys[0..n], r.c);
        }
    }

    fn face(self: *Frame, t: *const trk.Track, v: *const cam.View, fid: u16, decals: bool) void {
        const f = &t.faces[fid];
        const kept = project.build(self, &self.cache, t.verts, v, f, .{});
        if (kept == project.NONE) return;
        const key: u16 = @intCast(kept);
        if (self.fkey.len != 0) self.fkey[fid] = key;
        if (!decals) return;
        for (t.inner[f.inner_first..][0..f.inner_n]) |*d| _ = project.build(self, &self.cache, t.verts, v, d, .{ .fixed = key });
    }

    /// The key a ground face was kept with this frame, or null when it was culled or not reached (decals ride on it).
    pub fn faceKey(self: *const Frame, fid: u16) ?u16 {
        if (self.fkey.len == 0 or self.seen[fid] != self.seen_stamp) return null;
        return if (self.fkey[fid] == NO_KEY) null else self.fkey[fid];
    }
};
