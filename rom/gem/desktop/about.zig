// --------------------------------------------------------------------------
// Desk > Desktop Info... — a modal "about" box modelled on the classic Atari TOS
// "GEM Desktop" dialog: a centred double-framed box with an emblem, a heading,
// credit/version lines and an OK button. Laid out on the 8px cell grid.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");

pub const About = struct {
    active: bool = false,

    const W: i16 = 256; // 32 cells
    const H: i16 = 136; // 17 cells

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

        // Emblem (left) + heading/credits (right), TOS-style.
        drawZ(g, grid.x(3), grid.y(2), 40, gui.BLACK);
        g.text("GEM Desktop", grid.x(11), grid.y(2), gui.BLACK, gui.WHITE);
        g.text("Version 1.0", grid.x(11), grid.y(4), gui.BLACK, gui.WHITE);
        g.text("(c) 2026 shazz", grid.x(11), grid.y(6), gui.BLACK, gui.WHITE);

        g.frame(.{ .x = grid.x(3), .y = grid.y(9), .w = grid.w(26), .h = 1 }, gui.BLACK); // rule
        title(g, "A GEM-style ROM for ZigMachine", dx, grid.y(10), W);
        title(g, "Running on ZigOS", dx, grid.y(11), W);

        const bw: i16 = 64;
        const okx = gui.gcenter(dx, W, bw);
        if (g.buttonThick(.{ .x = okx, .y = grid.y(13), .w = bw, .h = 14 }, "OK", false, 3)) {
            self.active = false;
            return .ok;
        }
        return .none;
    }
};

// A blocky ZigMachine "Z" emblem: top + bottom bars joined by a diagonal band.
fn drawZ(g: *gui.Gui, x: i16, y: i16, s: i16, color: u8) void {
    const t: i16 = @max(4, @divTrunc(s, 5)); // bar / band thickness
    g.rect(.{ .x = x, .y = y, .w = s, .h = t }, color); // top bar
    g.rect(.{ .x = x, .y = y + s - t, .w = s, .h = t }, color); // bottom bar
    var row: i16 = t;
    while (row < s - t) : (row += 1) {
        const dxp = x + (s - t) - @divTrunc((row - t) * (s - t), s - 2 * t); // right->left
        g.blit.fill(g.fb, dxp, y + row, @intCast(t), 1, color);
    }
}

fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
