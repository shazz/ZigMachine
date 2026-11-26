// --------------------------------------------------------------------------
// RACER: the title screen (M5 step 4), drawn over the attract flyby after the frame is filled (and
// after the benchmark's view CRC, so the flyby's lap pins are the bare view's). Our own art: the
// KESTREL RACING logo in the scaled system font with its gradient and drop shadow, three speed
// stripes under it, the "press fire" line blinking at 1 Hz, the credit line. No ZigOS import.
// --------------------------------------------------------------------------
const menu = @import("menu.zig");

pub const LOGO_Y = 40;
pub const PROMPT = "PRESS FIRE OR ENTER";
pub const CREDIT = "AN ORIGINAL KESTREL GAME";

/// The logo, the stripes and the text panels over the flyby; the caller prints the lines it returns into the
/// panels (`frames` since the screen came up: the prompt blinks).
pub fn draw(p: menu.Px, font: []const u8, frames: u32) Lines {
    p.big(font, "KESTREL", 160 - 7 * 16, LOGO_Y, 4); // 7 glyphs of 32 pixels: x 48..272
    p.big(font, "RACING", 160 - 6 * 12, LOGO_Y + 38, 3);
    for (menu.LOGO, 0..) |c, k| {
        const y: i32 = LOGO_Y + 68 + @as(i32, @intCast(k)) * 4;
        p.rect(40 + @as(i32, @intCast(k)) * 12, y, 240 - @as(i32, @intCast(k)) * 24, 2, c);
    }
    p.panel(76, 138, 168, 12);
    p.panel(60, 164, 200, 12);
    return .{ .prompt = frames % 60 < 40, .credit = true };
}

/// Which text lines the caller prints this frame (the panels are drawn either way).
pub const Lines = struct { prompt: bool, credit: bool };

pub const PROMPT_XY = [2]i16{ 160 - PROMPT.len * 4, 140 };
pub const CREDIT_XY = [2]i16{ 160 - CREDIT.len * 4, 166 };
