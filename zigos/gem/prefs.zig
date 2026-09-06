// --------------------------------------------------------------------------
// Options > Set Preferences: a modal GEM dialog (centred, double frame, no
// shadow, like the real SET PREFERENCES) to pick the screen resolution and the
// desktop background colour. Mouse-only: each RGB channel has -/+ steppers (±8,
// clamped 0..255); the colour previews live via the DESK palette entry.
//
// Split out of gem.zig unchanged. Phase 4 of the GUI refactor re-expresses this
// on the grid engine; for now it stays hand-laid.
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
    const W: i16 = 252;
    const H: i16 = 152;

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
        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE); // no shadow (dialogs are flat; only windows cast one)
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK); // GEM double frame:
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK); // outer + inner
        title(g, "SET PREFERENCES", dx, dy + 10, W);

        // Background colour: R/G/B steppers on a grid + a live swatch.
        g.text("Background colour:", dx + 22, dy + 32, gui.BLACK, gui.WHITE);
        self.cr = channel(g, dx + 30, dy + 50, "R", self.cr);
        self.cg = channel(g, dx + 30, dy + 68, "G", self.cg);
        self.cb = channel(g, dx + 30, dy + 86, "B", self.cb);
        g.fb.setPaletteEntry(gui.DESK, .{ .r = self.cr, .g = self.cg, .b = self.cb, .a = 255 }); // live preview
        g.rect(.{ .x = dx + 158, .y = dy + 50, .w = 66, .h = 48 }, gui.DESK); // swatch
        g.frame(.{ .x = dx + 158, .y = dy + 50, .w = 66, .h = 48 }, gui.BLACK);

        g.text("Resolution:", dx + 22, dy + 110, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = dx + 116, .y = dy + 108, .w = 44, .h = 12 }, "Low", !self.medium)) self.medium = false;
        if (g.button(.{ .x = dx + 166, .y = dy + 108, .w = 60, .h = 12 }, "Medium", self.medium)) self.medium = true;

        if (g.buttonThick(.{ .x = dx + 52, .y = dy + 128, .w = 56, .h = 14 }, "OK", false, 3)) return .ok;
        if (g.buttonThick(.{ .x = dx + 138, .y = dy + 128, .w = 70, .h = 14 }, "Cancel", false, 2)) return .cancel;
        return .none;
    }
};

// Centre a title string in a `width`-wide area starting at x.
fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
