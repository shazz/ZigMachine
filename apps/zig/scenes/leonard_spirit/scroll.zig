// --------------------------------------------------------------------------
// The 6x6 scrolltext as ONE pre-rendered strip (CODEF's scroll_canvas): the
// whole text laid out at compile time, 6 pixels a letter like the `leonard`
// cart's scroller, ink already at its merged-palette index, followed by the
// text's first 67 letters again so a 400-pixel window never wraps. Each frame
// the window moves 2 pixels and is ONE keyed CHISEL blit from cart RAM.
// --------------------------------------------------------------------------
const std = @import("std");

pub const CW = 6; // letter width and height
pub const SPEED = 2;
pub const VIEW = 400; // the overscan window
const FONT_FIRST = ' ';
const FONT_GLYPHS = 60; // ' ' .. '[' in font.raw, 6x6 bytes each

pub fn Strip(comptime font: []const u8, comptime text: []const u8, comptime ink: u8) type {
    return struct {
        pub const TEXT_W: u32 = text.len * CW; // one lap, in pixels
        const WRAP = (VIEW + CW - 1) / CW; // letters repeated after the end
        pub const W: u32 = (text.len + WRAP) * CW;

        pub const pixels: [CW * W]u8 = blk: {
            @setEvalBranchQuota(4_000_000);
            var px = [_]u8{0} ** (CW * W);
            for (0..text.len + WRAP) |i| {
                const c = text[i % text.len];
                if (c < FONT_FIRST or c - FONT_FIRST >= FONT_GLYPHS) @compileError("scrolltext: no glyph for a character");
                const g = @as(u32, c - FONT_FIRST) * CW * CW;
                for (0..CW) |y| for (0..CW) |x| {
                    if (font[g + y * CW + x] != 0) px[y * W + i * CW + x] = ink;
                };
            }
            break :blk px;
        };

        /// The window's left edge in the strip on scroll tick t.
        pub fn windowX(t: u32) u16 {
            return @intCast((t * SPEED) % TEXT_W);
        }
    };
}
