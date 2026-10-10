// The F11 frame-rate overlay (docs/FPGA_GLASS.md, "The frame-rate overlay").
// While the menu is closed, the OSD window moves to the top-left corner under
// CTRL_OSD_STATS, where every plain-space cell is transparent: only "FPS 38.2"
// covers the picture. Opening the menu brings back the centred, opaque window;
// closing it brings the overlay back if it was on. The toggle is a setting
// (glass.cfg `fps`), so it survives a restart.
//
// A PL older than VERSION_OSD_STATS has neither the bit nor REG_OSD_POS: there
// F11 does nothing (it would otherwise show an opaque blank window mid-screen),
// and the glass never refuses that PL for it.
const std = @import("std");
const map = @import("map.zig");
const App = @import("app.zig").App;
const cart = @import("app_cart.zig");

/// Where the window goes: 16 pixels in from the corner, clear of a TV's overscan.
pub const CORNER: u32 = 16 << map.OSD_POS_X_SHIFT | 16 << map.OSD_POS_Y_SHIFT;
pub const TEXT_MAX = 12;

pub fn supported(version: u32) bool {
    return version >= map.VERSION_OSD_STATS;
}

pub fn on(app: *const App) bool {
    return app.pl_stats and app.menu.settings.fps and !app.open;
}

/// F11 with the menu closed. With the menu open it does nothing: the menu
/// owns the window then, and the toggle is saved where the menu can't see it.
pub fn toggle(app: *App) void {
    if (app.open) return;
    if (!app.pl_stats) return std.log.info("F11: this PL (before 1.4.0) has no frame-rate overlay", .{});
    app.menu.settings.fps = !app.menu.settings.fps;
    app.settings_dirty = true;
    place(app);
    draw(app);
    cart.saveSettings(app);
}

/// CTRL's OSD bits and the window's place, for the state the app is in now.
pub fn place(app: *App) void {
    const ctrl = app.regs.read(map.REG_CTRL) & ~(map.CTRL_OSD | map.CTRL_OSD_STATS);
    const bits = if (app.open) map.CTRL_OSD else if (on(app)) map.CTRL_OSD | map.CTRL_OSD_STATS else 0;
    if (app.pl_stats) app.regs.write(map.REG_OSD_POS, if (on(app)) CORNER else map.OSD_POS_RESET);
    app.regs.write(map.REG_CTRL, ctrl | bits);
}

/// Row 0 shows the rate, the rest is blank (transparent). Called on every tick:
/// the rate itself changes once a second (stats.zig), and only changed cells
/// cross the bus, so a redraw that finds nothing new writes nothing.
pub fn draw(app: *App) void {
    if (!on(app)) return;
    var buf: [TEXT_MAX]u8 = undefined;
    app.osd.clear();
    app.osd.put(0, 0, text(app.stats.fps_x10, &buf), false);
    _ = app.osd.flush(app.regs);
}

/// "FPS 38.2", or "FPS --.-" until a whole second has been measured.
pub fn text(fps_x10: ?u32, buf: *[TEXT_MAX]u8) []const u8 {
    const v = fps_x10 orelse return "FPS --.-";
    return std.fmt.bufPrint(buf, "FPS {d}.{d}", .{ @min(v / 10, 9999), v % 10 }) catch unreachable;
}
