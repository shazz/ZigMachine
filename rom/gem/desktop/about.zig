// --------------------------------------------------------------------------
// Desk > Desktop Info... — a modal "about" box modelled on the classic Atari TOS
// "GEM Desktop" dialog: a centred double-framed box with the machine's boot logo,
// a heading, version/credit lines and an OK button. Laid out on the 8px cell grid.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");

// The same logo the boot ROM shows (machine/assets/logo), drawn here at half size.
const LOGO = @embedFile("../assets/logo/zig_logo.raw"); // 65x60, 8-bit indexed
const LOGO_PAL = @embedFile("../assets/logo/zig_logo.pal"); // 256 x [r,g,b,a]
const LOGO_W: usize = 65;
const LOGO_H: usize = 60;
const LOGO_DRAW_H: i16 = LOGO_H / 2; // blitted at half size

pub const About = struct {
    active: bool = false,
    phase: u16 = 0, // advances every frame -> the logo's colours scroll

    const W: i16 = 296; // 37 cells
    const H: i16 = 128; // 16 cells
    const DENSE: i16 = 10; // consecutive text lines (8px glyph + leading)
    const RULE_CHARS: usize = 31; // the underscore rule, 3 cells in from each side

    pub fn open(self: *About) void {
        self.active = true;
    }

    pub const Result = enum { none, ok };

    // The TOS 1.00 "GEM Desktop" box: the product line, TOS, a rule, then the
    // logo with the copyright block beside it — everything centred but the logo.
    pub fn process(self: *About, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE); // flat (no shadow)
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK); // GEM double frame
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK);

        title(g, "GEM", dx, grid.y(1) + 2, W);
        title(g, "Graphics Environment Manager", dx, grid.y(2) + 2, W);
        title(g, "TOS", dx, grid.y(4), W);
        // TOS draws the rule as a ROW OF UNDERSCORES in the system font, not as a
        // hairline — the character's own bar, with its cell's leading above it.
        const rule = [_]u8{'_'} ** RULE_CHARS;
        g.text(&rule, grid.x(3), grid.y(5), gui.BLACK, gui.WHITE);

        const tx = grid.x(9);
        const cy = grid.y(7); // the copyright block runs on CONSECUTIVE lines
        self.phase +%= 1;
        // Centre the mark on the block of text beside it.
        drawLogo(g, grid.x(3), cy + @divTrunc(4 * DENSE - LOGO_DRAW_H, 2), self.phase);
        g.text("Copyright (c) 2026", tx, cy, gui.BLACK, gui.WHITE);
        g.text("ATARI CORP.", tx, cy + DENSE, gui.BLACK, gui.WHITE);
        g.text("Digital Research, Inc.", tx, cy + 2 * DENSE, gui.BLACK, gui.WHITE);
        g.text("All Rights Reserved.", tx, cy + 3 * DENSE, gui.BLACK, gui.WHITE);

        const bw: i16 = 64;
        if (g.buttonThick(.{ .x = gui.gcenter(dx, W, bw), .y = grid.y(13), .w = bw, .h = 14 }, "OK", false, 3)) {
            self.active = false;
            return .ok;
        }
        return .none;
    }
};

// Blit the indexed boot logo at half size. Light source pixels stay transparent
// so the white dialog shows through; the dark ones — the "Z1" mark itself — are
// painted from the spectrum ramp indexed by SCANLINE, and `phase` walks that
// index every frame, so the rainbow scrolls up through the logo the way an ST
// intro's raster bars do.
const RAINBOW_SPEED: u16 = 4; // frames per colour step (~15 steps/second at 60fps)

fn drawLogo(g: *gui.Gui, x: i16, y: i16, phase: u16) void {
    const shift: u16 = (phase / RAINBOW_SPEED) % gui.RAINBOW_N;
    var sy: usize = 0;
    while (sy < LOGO_H) : (sy += 2) {
        const band: u16 = (@as(u16, @intCast(sy / 2)) + shift) % gui.RAINBOW_N;
        const c: u8 = gui.RAINBOW0 + @as(u8, @intCast(band));
        var sx: usize = 0;
        while (sx < LOGO_W) : (sx += 2) {
            const idx: usize = LOGO[sy * LOGO_W + sx];
            const sum: u16 = @as(u16, LOGO_PAL[idx * 4]) + LOGO_PAL[idx * 4 + 1] + LOGO_PAL[idx * 4 + 2];
            if (sum < 300) // dark -> a band of the spectrum
                g.plot(x + @as(i16, @intCast(sx / 2)), y + @as(i16, @intCast(sy / 2)), c);
        }
    }
}

fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
