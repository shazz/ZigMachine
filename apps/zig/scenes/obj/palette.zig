// --------------------------------------------------------------------------
// OBJ demo: the palettes, written when the shading mode changes (never per
// frame). The float here runs once a key press: these are the old cart's own
// formulas, kept so its colours stay the same.
//   FLAT / SOFT / WIRE / HIDDEN: a 12-step teal->white ramp at 1..12
//   GLENZ: the six face bits' colours summed, 1..63; GLENZ NEST instead the
//   Amiga red and white glenz (NEST_GLENZ, built at compile time)
//   GOURAUD: the same ramp in 32 steps, 1..32
//   TEXTURE: the wall texture's own 64 colours at 1..64 (textures.zig)
//   ENVMAP: Natrium's 13 greys at 1..13 (its ST colours 000/333/555/777, undithered)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const draw = @import("draw.zig");
const xform = @import("xform.zig");
const textures = @import("textures.zig");

pub const TEXT: u8 = 200;

/// The entries every mode shares: the see-through 0, the text and the wire ink.
pub fn fixed(fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
    fb.setPaletteEntry(TEXT, .{ .r = 235, .g = 235, .b = 245, .a = 255 });
    fb.setPaletteEntry(draw.WIRE_INK, .{ .r = 120, .g = 235, .b = 255, .a = 255 });
}

pub fn program(fb: *zg.LogicalFB, mode: draw.Mode, nest: bool) void {
    switch (mode) {
        .glenz => if (nest) nestGlenz(fb) else glenz(fb),
        .gouraud => ramp(fb, xform.GOURAUD_TOP + 1),
        .texture => for (0..64) |i| {
            const c = textures.WALL_PAL[3 * i ..][0..3];
            fb.setPaletteEntry(@intCast(1 + i), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
        },
        .envmap => for (0..13) |l| { // Natrium's 13 levels: 000 -> 333 -> 555 -> 777 (ST greys), 4 steps each
            const li: u32 = @intCast(l);
            const seg: u32 = @min(li / 4, 2);
            const g0 = [4]u32{ 0, 96, 160, 224 };
            const g: u8 = @intCast(g0[seg] + (g0[seg + 1] - g0[seg]) * (li - 4 * seg) / 4);
            fb.setPaletteEntry(@intCast(1 + l), .{ .r = g, .g = g, .b = g, .a = 255 });
        },
        else => ramp(fb, xform.FLAT_LEVELS),
    }
}

fn glenz(fb: *zg.LogicalFB) void {
    const hue = [6][3]f32{
        .{ 0.95, 0.3, 0.4 }, .{ 0.3, 0.9, 0.5 },  .{ 0.98, 0.8, 0.2 },
        .{ 0.3, 0.6, 0.98 }, .{ 0.85, 0.4, 0.95 }, .{ 0.3, 0.9, 0.9 },
    };
    var i: u8 = 1;
    while (i < 64) : (i += 1) {
        var acc = [3]f32{ 0, 0, 0 };
        for (0..6) |k| if (i & (@as(u8, 1) << @intCast(k)) != 0) {
            for (0..3) |c| acc[c] += hue[k][c];
        };
        fb.setPaletteEntry(i, .{ .r = chan(acc[0] * 0.72), .g = chan(acc[1] * 0.72), .b = chan(acc[2] * 0.72), .a = 255 });
    }
}

/// teal -> white in `n` steps at 1..n
fn ramp(fb: *zg.LogicalFB, n: u8) void {
    var l: u8 = 0;
    while (l < n) : (l += 1) {
        const f: f32 = @as(f32, @floatFromInt(l)) / @as(f32, @floatFromInt(n - 1));
        fb.setPaletteEntry(1 + l, .{
            .r = chan(0.15 + 0.85 * f),
            .g = chan(0.45 + 0.55 * f),
            .b = chan(0.55 + 0.45 * f),
            .a = 255,
        });
    }
}

/// `n` steps from colour a to colour b at first..first+n-1 (once a key press).
fn band(fb: *zg.LogicalFB, first: u8, n: u8, a: [3]f32, b: [3]f32) void {
    var l: u8 = 0;
    while (l < n) : (l += 1) {
        const f: f32 = @as(f32, @floatFromInt(l)) / @as(f32, @floatFromInt(n - 1));
        const g = f * f * (3 - 2 * f); // eased, so the highlight blooms instead of banding
        fb.setPaletteEntry(first + l, .{ .r = chan(a[0] + (b[0] - a[0]) * g), .g = chan(a[1] + (b[1] - a[1]) * g), .b = chan(a[2] + (b[2] - a[2]) * g), .a = 255 });
    }
}

fn chan(v: f32) u8 {
    return @intFromFloat(@max(@as(f32, 0), @min(v, 1.0)) * 255.0);
}

fn nestGlenz(fb: *zg.LogicalFB) void {
    for (NEST_GLENZ[1..], 1..) |c, i| fb.setPaletteEntry(@intCast(i), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
}

/// GLENZ NEST's 63 OR combinations, the classic Amiga red and white glenz.
/// A face ORs bit (index mod 6), so the bits set count the layers over a
/// pixel (popcount) and the even bits are the "white" faces, the odd ones the
/// "red": one layer is white or red, two or three are pinks to mid reds (the
/// more white faces, the paler), four and more deepen the red and never reach
/// white, so the inner shells still read in the middle of the nest.
pub const NEST_GLENZ: [64][3]u8 = blk: {
    var t: [64][3]u8 = undefined;
    t[0] = .{ 0, 0, 0 };
    for (1..64) |i| {
        const layers = @popCount(@as(u6, @intCast(i)));
        const white = @popCount(@as(u6, @intCast(i & 0b010101)));
        t[i] = switch (layers) {
            1 => if (white == 1) .{ 240, 240, 240 } else .{ 224, 32, 48 },
            2 => switch (white) {
                2 => .{ 248, 176, 192 },
                1 => .{ 232, 112, 136 },
                else => .{ 200, 40, 64 },
            },
            3 => if (white >= 2) .{ 216, 96, 120 } else .{ 176, 32, 56 },
            4 => .{ 144, 24, 48 },
            5 => .{ 120, 16, 40 },
            else => .{ 96, 8, 32 },
        };
    }
    break :blk t;
};
