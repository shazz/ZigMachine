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
// RACER: which tiles to draw. The converter bakes, for every camera tile and each of 16 yaw
// buckets, the tiles a ray DDA reaches within R_BAKE steps, far to near (tools/racer/pvs_bake.py
// has the definition); this file reads that list, and runs the same DDA at run time for a tile
// the converter did not bake (and as the test oracle: pvs_test.zig compares the two on every
// baked tile and bucket). An entry is `tile | distance << 10`; a distance is the fewest DDA
// steps, 0 = the camera's tile, 1 = its neighbours. Draw distance R keeps the entries <= R.
// No ZigOS import.
// --------------------------------------------------------------------------
const trk = @import("trk.zig");

pub const MAX_ENTRIES = 512;

pub fn tileOf(e: u16) u16 {
    return e & 0x3FF;
}

pub fn distOf(e: u16) u16 {
    return e >> 10;
}

/// The baked list for (tile, bucket): entries far to near, or null if the tile was not baked.
pub fn baked(t: *const trk.Track, tile: u32, bucket: u32) ?[]const u16 {
    const at = t.pvs_index[tile * trk.BUCKETS + bucket];
    if (at == trk.NOT_BAKED) return null;
    const n = t.pvs[at];
    return t.pvs[at + 1 ..][0..n];
}

/// The runtime DDA into `out` (far to near, empty tiles dropped): the number of entries.
pub fn dda(t: *const trk.Track, tile: u32, bucket: u32, r: u32, out: *[MAX_ENTRIES]u16) usize {
    var dist = [_]u8{0xFF} ** trk.TILES;
    dist[tile] = 0;
    const ox: i32 = @intCast(tile % trk.GRID);
    const oz: i32 = @intCast(tile / trk.GRID);
    if (r >= 1) neighbours(&dist, ox, oz);
    for (t.rays[0][bucket]) |d| walk(&dist, ox, oz, d[0], d[1], r);
    var n: usize = 0;
    var d: u32 = 8;
    while (true) : (d -= 1) {
        for (dist, 0..) |dd, i| {
            if (@as(u32, dd) == d and t.tile_first[i + 1] > t.tile_first[i]) {
                out[n] = @as(u16, @intCast(i)) | @as(u16, @intCast(d)) << 10;
                n += 1;
            }
        }
        if (d == 0) break;
    }
    return n;
}

fn neighbours(dist: *[trk.TILES]u8, ox: i32, oz: i32) void {
    var dz: i32 = -1;
    while (dz <= 1) : (dz += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            const x = ox + dx;
            const z = oz + dz;
            if ((dx != 0 or dz != 0) and x >= 0 and x < trk.GRID and z >= 0 and z < trk.GRID)
                dist[@intCast(z * trk.GRID + x)] = 1;
        }
    }
}

fn walk(dist: *[trk.TILES]u8, ox: i32, oz: i32, dx: i16, dz: i16, r: u32) void {
    const adx: i64 = @abs(dx);
    const adz: i64 = @abs(dz);
    if (adx == 0 and adz == 0) return;
    const sx: i32 = if (dx > 0) 1 else -1;
    const sz: i32 = if (dz > 0) 1 else -1;
    var x = ox;
    var z = oz;
    var ix: i64 = 0;
    var iz: i64 = 0;
    var step: u32 = 1;
    while (step <= r) : (step += 1) {
        const lhs = (32768 + 65536 * ix) * adz;
        const rhs = (32768 + 65536 * iz) * adx;
        if (adz == 0 or (adx != 0 and lhs < rhs)) {
            x += sx;
            ix += 1;
        } else if (adx == 0 or lhs > rhs) {
            z += sz;
            iz += 1;
        } else {
            x += sx;
            z += sz;
            ix += 1;
            iz += 1;
        }
        if (x < 0 or x >= trk.GRID or z < 0 or z >= trk.GRID) return;
        const i: usize = @intCast(z * trk.GRID + x);
        if (step < dist[i]) dist[i] = @intCast(step);
    }
}

/// The entries to draw: the baked list if there is one (skipping those past R), else the DDA
/// into `scratch`. Far to near either way.
pub fn visible(t: *const trk.Track, tile: u32, bucket: u32, r: u32, scratch: *[MAX_ENTRIES]u16) []const u16 {
    var list: []const u16 = undefined;
    if (baked(t, tile, bucket)) |b| {
        list = b;
    } else {
        list = scratch[0..dda(t, tile, bucket, t.rbake, scratch)];
    }
    var first: usize = 0;
    while (first < list.len and distOf(list[first]) > r) first += 1;
    if (break_thin) return thinned(list[first..], scratch);
    return list[first..];
}

/// The harness' --break pvs (key @, R82 bug pass): every other tile 2+ steps out dropped, as a sparse ray fan would.
pub var break_thin = false;

fn thinned(l: []const u16, out: *[MAX_ENTRIES]u16) []const u16 {
    var n: usize = 0;
    for (l) |e| {
        if (distOf(e) >= 2 and tileOf(e) & 1 == 1) continue;
        out[n] = e;
        n += 1;
    }
    return out[0..n];
}
