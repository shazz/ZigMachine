// --------------------------------------------------------------------------
// Options > Set Preferences: a modal GEM dialog (centred, double frame, no
// shadow, like the real SET PREFERENCES) to pick the screen resolution and the
// desktop background colour. Mouse-only: each RGB channel has -/+ steppers (±8,
// clamped 0..255); the colour previews live via the DESK palette entry.
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
    medium: bool = false,

    pub const Result = enum { none, ok, cancel };
    const W: i16 = 256; // 32 cells
    const H: i16 = 152; // 19 cells

    pub fn open(self: *Prefs, r: u8, g: u8, b: u8, medium: bool) void {
        self.* = .{ .active = true, .cr = r, .cg = g, .cb = b, .medium = medium };
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
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE); // no shadow (dialogs are flat; only windows cast one)
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK); // GEM double frame:
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK); // outer + inner
        title(g, "SET PREFERENCES", dx, grid.y(1) + 2, W);

        // Background colour: R/G/B steppers on the cell grid (pitch 2 cells) + swatch.
        g.text("Background colour:", grid.x(3), grid.y(4), gui.BLACK, gui.WHITE);
        self.cr = channel(g, grid.x(4), grid.y(6), "R", self.cr);
        self.cg = channel(g, grid.x(4), grid.y(8), "G", self.cg);
        self.cb = channel(g, grid.x(4), grid.y(10), "B", self.cb);
        g.fb.setPaletteEntry(gui.DESK, .{ .r = self.cr, .g = self.cg, .b = self.cb, .a = 255 }); // live preview
        const sw = gui.Rect{ .x = grid.x(20), .y = grid.y(6), .w = grid.w(9), .h = grid.h(6) };
        g.rect(sw, gui.DESK); // swatch
        g.frame(sw, gui.BLACK);

        g.text("Resolution:", grid.x(3), grid.y(13) + 2, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = grid.x(14), .y = grid.y(13), .w = 44, .h = 12 }, "Low", !self.medium)) self.medium = false;
        if (g.button(.{ .x = grid.x(20), .y = grid.y(13), .w = 60, .h = 12 }, "Medium", self.medium)) self.medium = true;

        // OK / Cancel: even margins + gap across the 3-cell-margin content width.
        const bw: i16 = 64;
        const cw = W - grid.w(6);
        const oky = grid.y(16);
        if (g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 0), .y = oky, .w = bw, .h = 14 }, "OK", false, 3)) return .ok;
        if (g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 1), .y = oky, .w = bw, .h = 14 }, "Cancel", false, 2)) return .cancel;
        return .none;
    }
};

// Centre a title string in a `width`-wide area starting at x.
fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
