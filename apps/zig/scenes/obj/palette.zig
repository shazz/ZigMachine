// --------------------------------------------------------------------------
// OBJ demo: the palettes, written when the shading mode changes (never per
// frame). The float here runs once a key press: these are the old cart's own
// formulas, kept so its colours stay the same.
//   FLAT / SOFT / WIRE / HIDDEN: a 12-step teal->white ramp at 1..12
//   GLENZ: the six face bits' colours summed, 1..63
//   GOURAUD: the same ramp in 32 steps, 1..32
// --------------------------------------------------------------------------
const zg = @import("zigos");
const draw = @import("draw.zig");
const xform = @import("xform.zig");

pub const TEXT: u8 = 200;

/// The entries every mode shares: the see-through 0, the text and the wire ink.
pub fn fixed(fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
    fb.setPaletteEntry(TEXT, .{ .r = 235, .g = 235, .b = 245, .a = 255 });
    fb.setPaletteEntry(draw.WIRE_INK, .{ .r = 120, .g = 235, .b = 255, .a = 255 });
}

pub fn program(fb: *zg.LogicalFB, mode: draw.Mode) void {
    switch (mode) {
        .glenz => glenz(fb),
        .gouraud => ramp(fb, xform.GOURAUD_TOP + 1),
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

fn chan(v: f32) u8 {
    return @intFromFloat(@max(@as(f32, 0), @min(v, 1.0)) * 255.0);
}
