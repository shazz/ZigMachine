// --------------------------------------------------------------------------
// zig3d_fixed's per-face steps, on fixed-point canvas pixels (PX fraction bits): the usability and
// facing tests, CanvasRenderer's 1 px overdraw push, and the depth order.
// Each is zig3d's (which says what three.js does), in integer arithmetic.
// --------------------------------------------------------------------------
const std = @import("std");
const Face = @import("zig3d.zig").Face;
const fm = @import("zig3d_fixed_math.zig");

/// One projected vertex in canvas pixels, 1 px = fm.ONE_PX (x right, y down).
pub const Screen = struct { x: i32, y: i32, usable: bool };

/// A face ready to fill, in canvas pixels (1 px = fm.ONE_PX). `depth` is its
/// centroid's distance in front of the camera, larger is farther (three.js
/// sorts by the centroid's NDC z, which grows with it). It is Q46, unrounded:
/// a symmetric mesh has faces whose depths differ by less than a Q16 step,
/// and three.js still orders them.
pub const Poly = struct { pts: [4][2]i32, n: u8, ink: u8, depth: i64 };

pub fn usable(f: Face, s: []const Screen) bool {
    for (f.v[0..f.n]) |i| if (!s[i].usable) return false;
    return true;
}

/// Projector's facing test. It is taken in divided clip space, where y points
/// up; canvas y points down, so a face clockwise there has a POSITIVE cross
/// product here.
pub fn clockwise(f: Face, s: []const Screen) bool {
    const a = s[f.v[0]];
    const b = s[f.v[1]];
    const c = s[f.v[2]];
    if (f.n == 3) return cross(a, b, c) > 0;
    const d = s[f.v[3]];
    return cross(a, b, d) > 0 or cross(c, d, b) > 0;
}

/// (p3 - p1) x (p2 - p1), its operands scaled down together when they would
/// overflow 64 bits (only the sign is used).
fn cross(p1: Screen, p2: Screen, p3: Screen) i64 {
    var d = [4]i64{ @as(i64, p3.x) - p1.x, @as(i64, p2.y) - p1.y, @as(i64, p3.y) - p1.y, @as(i64, p2.x) - p1.x };
    const sh = excess(@max(@max(@abs(d[0]), @abs(d[1])), @max(@abs(d[2]), @abs(d[3]))), 30);
    if (sh > 0) for (&d) |*v| {
        v.* >>= sh;
    };
    return d[0] * d[1] - d[2] * d[3];
}

/// How many bits `m` has above `bits` (0 when it fits).
fn excess(m: u64, comptime bits: u7) u6 {
    const have: u7 = 64 - @as(u7, @clz(m));
    return if (have > bits) @intCast(have - bits) else 0;
}

/// CanvasRenderer's overdraw: Face3 pushes (1,2) (2,3) (3,1); Face4 pushes
/// (1,2) (2,4) (4,1), then moves 3 away from the un-pushed 2 and 4.
pub fn overdraw(p: *Poly) void {
    const pt = &p.pts;
    if (p.n == 3) {
        push(&pt[0], &pt[1]);
        push(&pt[1], &pt[2]);
        push(&pt[2], &pt[0]);
        return;
    }
    var v2 = pt[1];
    var v4 = pt[3];
    push(&pt[0], &pt[1]);
    push(&pt[1], &pt[3]);
    push(&pt[3], &pt[0]);
    push(&pt[2], &v2);
    push(&pt[2], &v4);
}

/// Nb(a, b): a and b each move 1 px (fm.ONE_PX) apart along their line. The
/// difference is normalised to 30 bits first, so the integer square root has
/// full precision for a short edge and cannot overflow for a long one.
fn push(a: *[2]i32, b: *[2]i32) void {
    const dx: i64 = @as(i64, b[0]) - a[0];
    const dy: i64 = @as(i64, b[1]) - a[1];
    const m: u64 = @max(@abs(dx), @abs(dy));
    if (m == 0) return;
    const have: i32 = 64 - @as(i32, @clz(m));
    const sx = shift(dx, 30 - have);
    const sy = shift(dy, 30 - have);
    const len: i64 = @intCast(fm.isqrt(@intCast(sx * sx + sy * sy)));
    const inv = fm.pow2Over(30 + fm.PX, len); // |s| <= len keeps s*inv in 2^(30+PX)
    const ux: i32 = @intCast((sx * inv + (1 << 29)) >> 30);
    const uy: i32 = @intCast((sy * inv + (1 << 29)) >> 30);
    b[0] += ux;
    b[1] += uy;
    a[0] -= ux;
    a[1] -= uy;
}

fn shift(v: i64, by: i32) i64 {
    return if (by >= 0) v << @intCast(by) else v >> @intCast(-by);
}

/// Order `list` far to near, a face of equal depth staying after the ones
/// that came before it: zig3d's stable insertion sort. The sort moves 2-byte
/// indices, then each 40-byte face moves once into its place (every store is
/// a blocking DDR write on the board: moving whole faces per shift cost ~0.8
/// Mcycles a frame on TNT3's ball).
pub fn sortFarToNear(list: []Poly) void {
    if (list.len > MAX_SORT) return std.sort.insertion(Poly, list, {}, farther);
    var order: [MAX_SORT]u16 = undefined;
    for (list, 0..) |p, i| {
        var j = i;
        while (j > 0 and list[order[j - 1]].depth < p.depth) : (j -= 1) order[j] = order[j - 1];
        order[j] = @intCast(i);
    }
    // list[j] = old list[order[j]], one cycle of the permutation at a time;
    // order[cur] = cur marks a place filled
    for (0..list.len) |j| {
        if (order[j] == j) continue;
        const tmp = list[j];
        var cur = j;
        while (true) {
            const src = order[cur];
            order[cur] = @intCast(cur);
            if (src == j) {
                list[cur] = tmp;
                break;
            }
            list[cur] = list[src];
            cur = src;
        }
    }
}

const MAX_SORT = 1024;

fn farther(_: void, a: Poly, b: Poly) bool {
    return a.depth > b.depth;
}
