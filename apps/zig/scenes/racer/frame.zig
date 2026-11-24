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
// Cars will join the same sort (M2): one list, so a crest hides a car behind it.
// No ZigOS import: the Sink is a parameter.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const fx = @import("fx.zig");
const poly = @import("poly.zig");
const pvs = @import("pvs.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");
const facing = types.facing;
const offScreen = types.offScreen;
const xf = @import("xform.zig");

pub const BUCKETS = 1024;
pub const MAXP = 6144; // polygons kept a frame (the stress city at R = 8 stays under it); past it they are dropped, counted
pub const MAXV = types.MAXV;
pub const Rec = types.Rec;
pub const Stats = types.Stats;

pub const Frame = struct {
    cache: xf.Cache,
    kept: []Rec, // MAXP
    key: []u16, // MAXP
    order: []u16, // MAXP, far to near
    count: *[BUCKETS + 1]u32,
    seen: []u32, // a face's frame stamp
    seen_stamp: u32 = 0,
    entries: [pvs.MAX_ENTRIES]u16 = undefined,
    list: []const u16 = &.{},
    stats: Stats = .{},

    pub noinline fn visibility(self: *Frame, t: *const trk.Track, v: *const cam.View, r: u32) void {
        self.list = pvs.visible(t, v.tile, v.bucket, r, &self.entries);
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
                self.stats.faces += 1;
                const f = &t.faces[fid];
                if (f.flags & trk.FLAG_DUAL == 0 and facing(f, v) <= f.cp) {
                    self.stats.back += 1;
                    continue;
                }
                self.face(t, v, f, decals);
            }
        }
        self.stats.verts = self.cache.touched;
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
            for (0..r.n) |j| {
                xs[j] = r.x[j];
                ys[j] = r.y[j];
            }
            em.poly(xs[0..r.n], ys[0..r.n], r.c);
        }
    }

    fn face(self: *Frame, t: *const trk.Track, v: *const cam.View, f: *const trk.Face, decals: bool) void {
        const key = self.build(t, v, f, null) orelse return;
        if (!decals) return;
        for (t.inner[f.inner_first..][0..f.inner_n]) |*d| _ = self.build(t, v, d, key);
    }

    /// Project one face into `kept`; the key is the face's own (mean view depth) unless a parent's is given.
    /// Returns the key kept, or null when nothing is left to draw.
    fn build(self: *Frame, t: *const trk.Track, v: *const cam.View, f: *const trk.Face, parent_key: ?u16) ?u16 {
        const nv = f.nv;
        var es: [4]*xf.Entry = undefined;
        var all: u8 = 0xFF;
        var any_guard: u8 = 0;
        var zsum: i32 = 0;
        for (0..nv) |i| {
            es[i] = xf.get(&self.cache, v, t.verts, f.v[i]);
            all &= es[i].rej;
            any_guard |= es[i].guard;
            zsum += es[i].v[2];
        }
        if (all != 0) {
            self.stats.rejected += 1;
            return null;
        }
        var rec: Rec = undefined;
        if (clip.break_drop and any_guard != 0) return null;
        if (any_guard == 0) {
            rec.n = nv;
            for (0..nv) |i| {
                rec.x[i] = es[i].sx;
                rec.y[i] = es[i].sy;
            }
        } else if (!self.clipped(&rec, es[0..nv], any_guard)) {
            self.stats.rejected += 1;
            return null;
        }
        if (offScreen(&rec)) return null;
        rec.c = f.colour;
        const mean = if (nv == 4) zsum >> 2 else fx.mulsh16(zsum, 21845);
        const key: u16 = parent_key orelse @intCast(BUCKETS - 1 - @min(@max(mean >> 13, 0), BUCKETS - 1));
        return self.push(rec, key);
    }

    fn clipped(self: *Frame, rec: *Rec, es: []*xf.Entry, mask: u8) bool {
        var p = clip.Poly{};
        for (es) |e| {
            p.p[p.n] = e.v;
            p.n += 1;
        }
        clip.clip(&p, mask);
        if (p.n < 3) return false;
        self.stats.clipped += 1;
        rec.n = @intCast(p.n);
        for (p.p[0..p.n], 0..) |q, i| {
            const s = xf.project(q);
            rec.x[i] = @intCast(s.x);
            rec.y[i] = @intCast(s.y);
        }
        return true;
    }

    fn push(self: *Frame, rec: Rec, key: u16) ?u16 {
        const i = self.stats.polys;
        if (i == self.kept.len) {
            self.stats.dropped += 1;
            return null;
        }
        self.kept[i] = rec;
        self.key[i] = key;
        self.count[key + 1] += 1;
        self.stats.polys = i + 1;
        return key;
    }
};
