// --------------------------------------------------------------------------
// KESTREL BOOT: the emblem, a hovering kestrel seen from below, wings spread, tail
// fanned, drawn as polygons into a 128x128 texture at init (CHISEL AFFINE reads it).
// Original artwork for this cart. Colours are palette indices (art.zig gives them).
// Fill rule: even-odd, sampled at each texel's centre, later polygons on top.
// No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const SIDE: usize = 128; // texture side (U_MASK / V_MASK = 127)
pub const CENTRE: i32 = 64; // the texel that lands on the bird's screen position

// Palette indices (art.zig BASE).
pub const RUFOUS_LIGHT: u8 = 1;
pub const RUFOUS: u8 = 2;
pub const RUFOUS_DARK: u8 = 3;
pub const SLATE: u8 = 4;
pub const SLATE_DARK: u8 = 5;
pub const TIPS: u8 = 6;
pub const RIM: u8 = 7;
pub const SPOT: u8 = 8;

const P = [2]i16;
const Poly = struct { c: u8, p: []const P };

fn mirror(comptime pts: []const P) [pts.len]P {
    var out: [pts.len]P = undefined;
    for (pts, 0..) |q, i| out[i] = .{ 128 - q[0], q[1] };
    return out;
}

const L_INNER = [_]P{ .{ 60, 39 }, .{ 34, 39 }, .{ 24, 58 }, .{ 60, 56 } };
const L_TIPS = [_]P{ .{ 34, 39 }, .{ 3, 50 }, .{ 24, 58 } };
const L_RIM = [_]P{ .{ 60, 37 }, .{ 34, 37 }, .{ 3, 50 }, .{ 6, 50 }, .{ 34, 40 }, .{ 60, 40 } };
const L_TRAIL = [_]P{ .{ 24, 58 }, .{ 30, 55 }, .{ 60, 53 }, .{ 60, 56 } };
const L_SPOTS = [_]P{ .{ 42, 44 }, .{ 46, 44 }, .{ 46, 47 }, .{ 42, 47 } };
const L_SPOTS2 = [_]P{ .{ 50, 48 }, .{ 53, 48 }, .{ 53, 51 }, .{ 50, 51 } };

const POLYS = [_]Poly{
    .{ .c = SLATE, .p = &.{ .{ 59, 72 }, .{ 69, 72 }, .{ 81, 106 }, .{ 47, 106 } } }, // tail fan
    .{ .c = SLATE_DARK, .p = &.{ .{ 59, 72 }, .{ 64, 72 }, .{ 64, 98 }, .{ 50, 98 } } }, // its shaded half
    .{ .c = TIPS, .p = &.{ .{ 50, 97 }, .{ 78, 97 }, .{ 81, 104 }, .{ 47, 104 } } }, // the black band
    .{ .c = RIM, .p = &.{ .{ 47, 104 }, .{ 81, 104 }, .{ 81, 106 }, .{ 47, 106 } } }, // its pale tip
    .{ .c = RUFOUS_DARK, .p = &L_INNER },
    .{ .c = SLATE_DARK, .p = &L_TRAIL },
    .{ .c = TIPS, .p = &L_TIPS },
    .{ .c = RIM, .p = &L_RIM },
    .{ .c = SPOT, .p = &L_SPOTS },
    .{ .c = SPOT, .p = &L_SPOTS2 },
    .{ .c = RUFOUS_LIGHT, .p = &mirror(&L_INNER) },
    .{ .c = SLATE, .p = &mirror(&L_TRAIL) },
    .{ .c = TIPS, .p = &mirror(&L_TIPS) },
    .{ .c = RIM, .p = &mirror(&L_RIM) },
    .{ .c = SPOT, .p = &mirror(&L_SPOTS) },
    .{ .c = SPOT, .p = &mirror(&L_SPOTS2) },
    .{ .c = RUFOUS, .p = &.{ .{ 64, 30 }, .{ 71, 38 }, .{ 69, 66 }, .{ 64, 76 }, .{ 59, 66 }, .{ 57, 38 } } }, // body
    .{ .c = RUFOUS_LIGHT, .p = &.{ .{ 64, 32 }, .{ 70, 39 }, .{ 68, 64 }, .{ 64, 72 } } }, // its lit side
    .{ .c = SLATE, .p = &.{ .{ 64, 21 }, .{ 70, 26 }, .{ 69, 35 }, .{ 59, 35 }, .{ 58, 26 } } }, // head
    .{ .c = SLATE_DARK, .p = &.{ .{ 64, 21 }, .{ 58, 26 }, .{ 59, 35 }, .{ 64, 35 } } }, // its shaded side
    .{ .c = TIPS, .p = &.{ .{ 62, 30 }, .{ 66, 30 }, .{ 64, 34 } } }, // the beak
};

/// Is the texel centre (x + 0.5, y + 0.5) inside `p` (even-odd)? In doubled units: integers only.
fn inside(p: []const P, x: i32, y: i32) bool {
    const px = 2 * x + 1;
    const py = 2 * y + 1;
    var in = false;
    var j = p.len - 1;
    for (p, 0..) |a, i| {
        const b = p[j];
        j = i;
        const ay: i32 = 2 * @as(i32, a[1]);
        const by: i32 = 2 * @as(i32, b[1]);
        if ((ay > py) == (by > py)) continue;
        const ax: i32 = 2 * @as(i32, a[0]);
        const bx: i32 = 2 * @as(i32, b[0]);
        // x of the edge at py, compared without a divide: (px - ax)(by - ay) < (bx - ax)(py - ay)
        const lhs = (px - ax) * (by - ay);
        const rhs = (bx - ax) * (py - ay);
        if ((by > ay and lhs < rhs) or (by < ay and lhs > rhs)) in = !in;
    }
    return in;
}

/// Draws the bird into `tex` (SIDE * SIDE texels, 0 = transparent). Init only.
pub fn paint(tex: []u8) void {
    @memset(tex, 0);
    for (POLYS) |poly| {
        for (0..SIDE) |y| for (0..SIDE) |x| {
            if (inside(poly.p, @intCast(x), @intCast(y))) tex[y * SIDE + x] = poly.c;
        };
    }
}

test "bird: symmetric silhouette, transparent corners, body at the centre" {
    var tex: [SIDE * SIDE]u8 = undefined;
    paint(&tex);
    try std.testing.expectEqual(@as(u8, 0), tex[0]);
    try std.testing.expectEqual(RUFOUS, tex[50 * SIDE + 60]);
    // Mirrored polygons (128 - x) put texel x opposite 127 - x; a texel centre exactly on a
    // slanted edge goes in on one side and out on the other, so a handful may differ.
    var differ: u32 = 0;
    for (0..SIDE) |y| for (0..SIDE / 2) |x| {
        differ += @intFromBool((tex[y * SIDE + x] != 0) != (tex[y * SIDE + (SIDE - 1 - x)] != 0));
    };
    try std.testing.expect(differ <= 8);
}
