// --------------------------------------------------------------------------
// The fading snakes' colours (show.zig says why the fade is a dissolve plus a
// colour ramp): palette entries `first`..+2, the ball's three shades, run
// from the picture's main colour (level 0) to the record's ball (level
// FADE_LEVELS) in integer steps, (from * (16 - n) + to * n) / 16. Three
// palette writes on a frame whose level moved, none on the others.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const show = @import("show.zig");

pub fn shades(fb: *zg.LogicalFB, from: zg.Color, to: *const [3]zg.Color, first: u8, level: u32) void {
    for (to, 0..) |c, i| {
        fb.setPaletteEntry(first + @as(u8, @intCast(i)), .{
            .r = mix(from.r, c.r, level),
            .g = mix(from.g, c.g, level),
            .b = mix(from.b, c.b, level),
            .a = c.a,
        });
    }
}

pub fn mix(from: u8, to: u8, n: u32) u8 {
    return @intCast((@as(u32, from) * (show.FADE_LEVELS - n) + @as(u32, to) * n) / show.FADE_LEVELS);
}
