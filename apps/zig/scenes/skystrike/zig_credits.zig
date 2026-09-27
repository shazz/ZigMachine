// --------------------------------------------------------------------------
// ZIG mode's music credits on the title: one line in the bottom border just
// above the title's credits scroller (zig_scroller.zig), which has the band
// under it. The three modules and their licences take turns, each centred
// for CYCLE frames, while the title's scroller runs (2006), in the
// scroller's own white (it fades with the screen). Both lines are in the
// border's 29 lines above the monitor's frame (hud_bottom_margin). Overlay
// only: no game state, and ORIGINAL never shows it.
// --------------------------------------------------------------------------
const flow = @import("flow.zig");
const text = @import("text.zig");
const set = @import("zig_settings.zig");
const scroller = @import("zig_scroller.zig");

const W: usize = 400;
/// Its first line: two clear lines above the scroller's.
pub const Y: usize = set.scroller_y - 10;
/// Frames each line stays (3 s at 50 Hz).
const CYCLE: usize = 150;

const LINES = [_][]const u8{
    "MUSIC FROM THE MOD ARCHIVE",
    "Explore the sky - BLuRry - CC BY-SA 4.0",
    "The Hawk's Claw - Drozerix - Public Domain",
    "dog75 - Songerson - CC BY 4.0",
};

comptime {
    if (Y < set.screen_y + 200) @compileError("the credits must be in the bottom border, under the screen");
    if (set.scroller_y + 8 > 280 - set.hud_bottom_margin) @compileError("the scroller must clear the monitor's frame");
    for (LINES) |l| {
        if (l.len * 8 > W) @compileError("a credits line is wider than the frame");
        for (l) |c| if (c < 32) @compileError("a credits line has a control character");
    }
}

var frames: usize = 0;
pub var shown: bool = false;

/// Over the bottom border zig_scroller.draw painted.
pub fn draw(ov: []u8) void {
    shown = flow.pc == .l2006;
    if (!shown) {
        frames = 0;
        return;
    }
    const line = LINES[frames / CYCLE % LINES.len];
    frames += 1;
    const x0 = (W - line.len * 8) / 2;
    for (line, 0..) |c, k| {
        const g = text.glyph(c);
        for (0..8) |j| for (0..8) |i| {
            if (g[j] >> @intCast(7 - i) & 1 != 0) ov[(Y + j) * W + x0 + k * 8 + i] = scroller.INK;
        };
    }
}
