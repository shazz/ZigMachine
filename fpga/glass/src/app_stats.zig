// The F11 frame-rate overlay (docs/FPGA_GLASS.md, "The frame-rate overlay").
// While the menu is closed, the OSD window moves to the top-left corner under
// CTRL_OSD_STATS, where every plain-space cell is transparent: only "FPS 38.2"
// and, under it, the sound CPU's line ("BARD SNDH nat 43%/51%": who plays the
// music, the player and its mode, the load now/peak; snd_info.zig) cover the picture. Opening the menu brings back the centred, opaque window;
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
const snd_info = @import("snd_info.zig");

/// Where the window goes: 16 pixels in from the corner, clear of a TV's overscan.
pub const CORNER: u32 = 16 << map.OSD_POS_X_SHIFT | 16 << map.OSD_POS_Y_SHIFT;
pub const TEXT_MAX = 12;
/// The BARD line is read again once a second (ticks are 100 ms, main.zig): the load is
/// per render, so a faster line flickers between renders, and the rate changes no faster.
pub const BARD_TICKS = 10;

/// The BARD line as last read: the overlay redraws every tick, from this.
pub const Bard = struct {
    buf: [map.OSD_COLS]u8 = undefined,
    len: usize = 0, // 0: read it on the next draw
    at: u32 = 0, // App.ticks when read
};

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
    app.bard.len = 0; // shown now, not up to a second late
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

/// Row 0 shows the rate, row 1 the BARD line, the rest is blank (transparent). Called on every tick:
/// the rate itself changes once a second (stats.zig), and only changed cells
/// cross the bus, so a redraw that finds nothing new writes nothing.
pub fn draw(app: *App) void {
    if (!on(app)) return;
    var buf: [TEXT_MAX]u8 = undefined;
    app.osd.clear();
    app.osd.put(0, 0, text(app.stats.fps_x10, &buf), false);
    if (app.bard.len == 0 or app.ticks -% app.bard.at >= BARD_TICKS) {
        // As the debug page: with no cart running the mailbox is the last cart's.
        const info = if (app.current != null) snd_info.read(app.ddr) else snd_info.Info{};
        app.bard.len = bardText(&info, &app.bard.buf).len;
        app.bard.at = app.ticks;
    }
    app.osd.put(0, 1, app.bard.buf[0..app.bard.len], false);
    _ = app.osd.flush(app.regs);
}

/// "FPS 38.2", or "FPS --.-" until a whole second has been measured.
pub fn text(fps_x10: ?u32, buf: *[TEXT_MAX]u8) []const u8 {
    const v = fps_x10 orelse return "FPS --.-";
    return std.fmt.bufPrint(buf, "FPS {d}.{d}", .{ @min(v / 10, 9999), v % 10 }) catch unreachable;
}

/// "BARD SNDH nat 43%/51%" (the debug page's music row, snd_info.ok), "BARD idle" with
/// no music, "BARD ?" when the firmware cannot say.
pub fn bardText(i: *const snd_info.Info, buf: *[map.OSD_COLS]u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    switch (i.state) {
        .no_cart => w.writeAll("BARD idle") catch {},
        .off => w.writeAll("BARD off: no audio in fw") catch {},
        .old_fw, .busy, .bad_version => w.writeAll("BARD ?") catch {},
        .ok => snd_info.ok(&w, i),
    }
    return w.buffered();
}
