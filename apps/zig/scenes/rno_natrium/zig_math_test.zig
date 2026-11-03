// --------------------------------------------------------------------------
// NATRIUM ZIG mode: native tests of zig_math.zig (run from apps/zig/scene_tests.zig).
// The tunnel formula is held to the ORIGINAL's 160x100 table: at every cell
// it must name the same texel to within one (u wraps at 128), and the hole
// must be the table's own zero entries.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const M = @import("zig_math.zig");

/// The table entry ($144C8, little-endian in TEXT) as (u, v) texels, as chunky_box.zig reads it.
fn tableUV(i: usize) [2]i32 {
    const o: u32 = (@as(u32, A.tunnel_map[2 * i + 1]) << 8) | A.tunnel_map[2 * i];
    const off = ((o >> 9) << 8) | (o & 0xFE);
    return .{ @intCast((off & 0xFE) >> 1), @intCast(off >> 8) };
}

fn wrapDiff(a: i32, b: i32) i32 {
    return @intCast(@abs(@mod(a - b + 64, 128) - 64));
}

test "tunnel: the formula is the original table, texel for texel within one" {
    var worst_u: i32 = 0;
    var worst_v: i32 = 0;
    var holes: usize = 0;
    for (0..100) |cy| for (0..160) |cx| {
        // the cell's centre in half pixels from (79.5, 49.5) cells = (320, 200) half pixels
        const dx2: i32 = @as(i32, @intCast(cx)) * 4 + 2 - 320;
        const dy2: i32 = @as(i32, @intCast(cy)) * 4 + 2 - 200;
        const t = tableUV(cy * 160 + cx);
        const e = M.tunnelEntry(dx2, dy2);
        if (t[0] == 0 and t[1] == 0) {
            holes += 1;
            try std.testing.expectEqual(@as(u16, 0), e);
            continue;
        }
        try std.testing.expect(e != 0);
        worst_u = @max(worst_u, wrapDiff(e & 127, t[0]));
        // at the hole's rim (v near 128, r ~ 8 cells) 512 / r moves 2 texels a quarter cell
        const dv = wrapDiff(e >> 8, t[1]);
        if (t[1] >= 118) try std.testing.expect(dv <= 2) else worst_v = @max(worst_v, dv);
    };
    try std.testing.expect(holes > 150); // the table's hole: 208 cells
    try std.testing.expect(worst_u <= 1);
    try std.testing.expect(worst_v <= 1);
}

test "angle: the four axes and an octant" {
    try std.testing.expectEqual(@as(u32, 0), M.angle(5, 0));
    try std.testing.expectEqual(@as(u32, 32 << 8), M.angle(0, 5)); // down
    try std.testing.expectEqual(@as(u32, 64 << 8), M.angle(-5, 0));
    try std.testing.expectEqual(@as(u32, 96 << 8), M.angle(0, -5));
    try std.testing.expectEqual(@as(u32, 16 << 8), M.angle(7, 7));
    try std.testing.expectEqual(@as(u32, 112 << 8), M.angle(7, -7));
}

test "shades: the box's ends are its pens, its middle the mean of two" {
    const pal = [16]u16{ 0x000, 0, 0, 0, 0x421, 0, 0, 0, 0x652, 0, 0, 0, 0x777, 0, 0, 0 };
    const st = @import("st.zig");
    try std.testing.expectEqual(st.stColor(0x000), M.boxShade(&pal, 0));
    try std.testing.expectEqual(st.stColor(0x421), M.boxShade(&pal, 2));
    try std.testing.expectEqual(st.stColor(0x777), M.boxShade(&pal, 6));
    // shade 1 = pens 0 and 4: half of $421's channels, rounded
    try std.testing.expectEqual(@as(u32, 0xFF00_0000 | 18 << 16 | 36 << 8 | 73), M.boxShade(&pal, 1));
}

test "env levels: 0 is pen 0, 12 is pen 12, 4 the picture's grey (pen 4)" {
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = @intCast(i * 0x111 & 0x777);
    const st = @import("st.zig");
    try std.testing.expectEqual(st.stColor(pal[0]), M.envLevel(&pal, 0));
    try std.testing.expectEqual(st.stColor(pal[4]), M.envLevel(&pal, 4));
    try std.testing.expectEqual(st.stColor(pal[12]), M.envLevel(&pal, 12));
}
