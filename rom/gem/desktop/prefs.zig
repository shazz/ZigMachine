// --------------------------------------------------------------------------
// Options > Set Preferences: a modal GEM dialog (centred, double frame, no
// shadow, like the real SET PREFERENCES) to pick the screen resolution and the
// desktop background colour. Mouse-only: each RGB channel has -/+ steppers (±8,
// clamped 0..255); the colour previews live via the DESK palette entry.
//
// The resolution is a row of three radio buttons: Low, Medium, and Desk (the
// 640x480 desk mode at 1:1, HW 1.17.0, docs/GEM_DESK_MODE.md). Desk is greyed
// where the machine has no desk mode (the shell asked hwDeskAvailable).
//
// Laid out on the 8px character-cell grid engine (gui.Grid / gui.hspread) so the
// margins and button row are even instead of hand-tuned pixels.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");

pub const Prefs = struct {
    active: bool = false,
    cr: u8 = 1,
    cg: u8 = 160,
    cb: u8 = 164,
    res: gui.ScreenMode = .low,
    desk_ok: bool = false, // the machine shows the desk mode

    pub const Result = enum { none, ok, cancel };
    const W: i16 = 256; // 32 cells: fits the 320-wide low-res screen
    const H: i16 = 152; // 19 cells
    const RES_W: i16 = 56; // a resolution button: "Medium" and a cell of margin

    pub fn open(self: *Prefs, r: u8, g: u8, b: u8, res: gui.ScreenMode, desk_ok: bool) void {
        self.* = .{ .active = true, .cr = r, .cg = g, .cb = b, .res = res, .desk_ok = desk_ok };
    }

    fn clampStep(v: u8, d: i16) u8 {
        return @intCast(@max(0, @min(255, @as(i16, v) + d)));
    }

    fn channel(g: *gui.Gui, x: i16, y: i16, label: []const u8, v: u8) u8 {
        var nv = v;
        g.text(label, x, y + 2, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = x + 14, .y = y, .w = 16, .h = 12 }, "-", false)) nv = clampStep(nv, -8);
        var buf: [3]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d:0>3}", .{nv}) catch "???";
        g.text(s, x + 36, y + 2, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = x + 62, .y = y, .w = 16, .h = 12 }, "+", false)) nv = clampStep(nv, 8);
        return nv;
    }

    pub fn process(self: *Prefs, g: *gui.Gui) Result {
        const dx = g.screen.centreX(W);
        const dy = g.screen.centreY(H);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE); // no shadow (dialogs are flat; only windows cast one)
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK); // GEM double frame:
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK); // outer + inner
        title(g, "SET PREFERENCES", dx, grid.y(1) + 2, W);

        // Background colour: R/G/B steppers on the cell grid (pitch 2 cells) + swatch.
        g.text("Background colour:", grid.x(3), grid.y(3), gui.BLACK, gui.WHITE);
        self.cr = channel(g, grid.x(4), grid.y(5), "R", self.cr);
        self.cg = channel(g, grid.x(4), grid.y(7), "G", self.cg);
        self.cb = channel(g, grid.x(4), grid.y(9), "B", self.cb);
        g.fb.setPaletteEntry(gui.DESK, .{ .r = self.cr, .g = self.cg, .b = self.cb, .a = 255 }); // live preview
        const sw = gui.Rect{ .x = grid.x(20), .y = grid.y(5), .w = grid.w(9), .h = grid.h(6) };
        g.rect(sw, gui.DESK); // swatch
        g.frame(sw, gui.BLACK);

        self.resolutionRow(g, grid);

        // OK / Cancel: even margins + gap across the 3-cell-margin content width.
        const bw: i16 = 64;
        const cw = W - grid.w(6);
        const oky = grid.y(16);
        if (g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 0), .y = oky, .w = bw, .h = 14 }, "OK", false, 3)) return .ok;
        if (g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 1), .y = oky, .w = bw, .h = 14 }, "Cancel", false, 2)) return .cancel;
        return .none;
    }

    // "Resolution:" over a row of three radio buttons spread across the content width.
    fn resolutionRow(self: *Prefs, g: *gui.Gui, grid: gui.Grid) void {
        g.text("Resolution:", grid.x(3), grid.y(11) + 2, gui.BLACK, gui.WHITE);
        if (g.button(resButton(grid, 0), "Low", self.res == .low)) self.res = .low;
        if (g.button(resButton(grid, 1), "Medium", self.res == .medium)) self.res = .medium;
        if (!self.desk_ok) return greyed(g, resButton(grid, 2), "Desk"); // no desk mode here
        if (g.button(resButton(grid, 2), "Desk", self.res == .desk)) self.res = .desk;
    }

    /// Where resolution button `i` (0 Low, 1 Medium, 2 Desk) sits.
    pub fn resButton(grid: gui.Grid, i: i16) gui.Rect {
        const cw = W - grid.w(6);
        return .{ .x = gui.hspread(grid.x(3), cw, 3, RES_W, i), .y = grid.y(13), .w = RES_W, .h = 12 };
    }
};

// A choice the machine cannot make, greyed as TOS greys one: the frame and the
// label in the menus' disabled ink (MGRAY), never pressed, never selected.
fn greyed(g: *gui.Gui, r: gui.Rect, label: []const u8) void {
    g.rect(r, gui.WHITE);
    g.frame(r, gui.MGRAY);
    const tx = r.x + @divTrunc(r.w - @as(i16, @intCast(label.len)) * 8, 2);
    g.text(label, tx, r.y + @divTrunc(r.h - 8, 2), gui.MGRAY, gui.WHITE);
}

// Centre a title string in a `width`-wide area starting at x.
fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
