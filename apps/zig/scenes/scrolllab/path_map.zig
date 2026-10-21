// --------------------------------------------------------------------------
// Mode 9's sample map: for each path point i and each of its 2*TILE samples k,
// the destination byte that sample lands on, or NONE. path.zig's frame used to
// work it out per sample, every frame: ~90,000 f32 multiply-adds and twice as
// many float->int conversions, each with its range checks, which took the lab
// to ~10 fps on the board. Where a sample lands depends on the point and k
// alone (not on the strip column, nor on the drift), so it is computed once,
// with the frame's own f32 expressions in the frame's own order (same bits),
// and the frame keeps only integers.
//
// 896 points x 64 samples x u16 = 114,688 B on zg.mem, taken once by alloc()
// (modes.init, once per cart load). It is filled on the first draw, because
// the offsets are bytes of the view being drawn, and again only if that view
// changes.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const TILE = @import("filters.zig").TILE;

pub const MAX_PTS = 896;
pub const NONE: u16 = 0xFFFF;
const K = 2 * TILE;

pub var offs: *[MAX_PTS][K]u16 = undefined;
/// The point draws nothing (a zero normal, or every sample off the view).
pub var empty: *[MAX_PTS]bool = undefined;
const Built = struct { ptr: usize = 0, stride: usize = 0, w: usize = 0, h: usize = 0, n: usize = 0 };
var built: Built = .{};

pub fn alloc() void {
    offs = zg.mem.mustAlloc([K]u16, MAX_PTS)[0..MAX_PTS];
    empty = zg.mem.mustAlloc(bool, MAX_PTS)[0..MAX_PTS];
}

/// True when the map is valid for `dst`; false when `dst` is too big for u16
/// offsets, and the caller draws the slow way.
pub fn ensure(dst: blit.Dst, pts: []const [2]f32, nrm: []const [2]f32) bool {
    if (dst.h == 0 or (dst.h - 1) * dst.stride + dst.w >= NONE) return false;
    const g = Built{ .ptr = @intFromPtr(dst.buf.ptr), .stride = dst.stride, .w = dst.w, .h = dst.h, .n = pts.len };
    if (std.meta.eql(built, g)) return true;
    for (pts, nrm, 0..) |p, nv, i| fillPoint(dst, p, nv, i);
    built = g;
    return true;
}

fn fillPoint(dst: blit.Dst, p: [2]f32, nv: [2]f32, i: usize) void {
    const row = &offs[i];
    var any = false;
    for (0..K) |k| {
        row[k] = NONE;
        if (nv[0] == 0 and nv[1] == 0) continue; // the frame skipped the point whole
        // path.zig's sample, verbatim: t, then p + n * t, then plot's clip
        const t = @as(f32, @floatFromInt(k)) * 0.5 - TILE / 2;
        const o = at(dst, p[0] + nv[0] * t, p[1] + nv[1] * t) orelse continue;
        // k odd: its row's even sample (same strip byte, same ink) was the
        // write just before; landing on the same byte again changes nothing
        if (k % 2 == 1 and row[k - 1] == o) continue;
        row[k] = o;
        any = true;
    }
    empty[i] = !any;
}

fn at(dst: blit.Dst, x: f32, y: f32) ?u16 {
    if (!(x >= 0 and y >= 0)) return null; // NaN-safe, and vramAlloc has no guard
    const ix: usize = @intFromFloat(x);
    const iy: usize = @intFromFloat(y);
    if (ix >= dst.w or iy >= dst.h) return null;
    return @intCast(iy * dst.stride + ix);
}
