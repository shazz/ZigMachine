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

pub const About = struct {
    active: bool = false,

    const W: i16 = 224; // 28 cells
    const H: i16 = 112; // 14 cells

    pub fn open(self: *About) void {
        self.active = true;
    }

    pub const Result = enum { none, ok };

    pub fn process(self: *About, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE); // flat (no shadow)
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK); // GEM double frame
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK);

        drawLogo(g, grid.x(3), grid.y(2)); // boot logo (left), ~32x30
        g.text("GEM Desktop", grid.x(9), grid.y(2), gui.BLACK, gui.WHITE);
        g.text("Version 1.0", grid.x(9), grid.y(4), gui.BLACK, gui.WHITE);
        g.text("(c) 2026 shazz", grid.x(9), grid.y(6), gui.BLACK, gui.WHITE);

        g.frame(.{ .x = grid.x(3), .y = grid.y(8), .w = grid.w(22), .h = 1 }, gui.BLACK); // rule
        title(g, "A GEM ROM for ZigMachine", dx, grid.y(9), W);

        const bw: i16 = 64;
        if (g.buttonThick(.{ .x = gui.gcenter(dx, W, bw), .y = grid.y(11), .w = bw, .h = 14 }, "OK", false, 3)) {
            self.active = false;
            return .ok;
        }
        return .none;
    }
};

// Blit the indexed boot logo at half size: dark palette entries become ink, light
// ones stay transparent so the white dialog shows through (a black "Z1" mark).
fn drawLogo(g: *gui.Gui, x: i16, y: i16) void {
    var sy: usize = 0;
    while (sy < LOGO_H) : (sy += 2) {
        var sx: usize = 0;
        while (sx < LOGO_W) : (sx += 2) {
            const idx: usize = LOGO[sy * LOGO_W + sx];
            const sum: u16 = @as(u16, LOGO_PAL[idx * 4]) + LOGO_PAL[idx * 4 + 1] + LOGO_PAL[idx * 4 + 2];
            if (sum < 300) // dark -> ink
                g.fb.setPixelValue(@intCast(x + @as(i16, @intCast(sx / 2))), @intCast(y + @as(i16, @intCast(sy / 2))), gui.BLACK);
        }
    }
}

fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
