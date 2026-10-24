// The frame budget over the App: the probe sampled every tick (budget.zig smooths it), the budget
// page's view (page_budget.zig), Shift+F11, and the F11 overlay's second line. Reads only.
const std = @import("std");
const map = @import("map.zig");
const App = @import("app.zig").App;
const budget = @import("budget.zig");
const vstat = @import("vstat.zig");
const page_budget = @import("page_budget.zig");

/// One look at the probe (main.zig's 100 ms tick). Nothing while no cart runs: the block is
/// then the last cart's, and the next cart starts from an empty history.
pub fn sample(app: *App) void {
    if (app.current == null) return app.frame_budget.reset();
    const info = vstat.read(app.ddr);
    if (budget.sample(&info)) |s| app.frame_budget.push(s);
}

pub fn view(app: *const App) page_budget.View {
    const r = if (app.current != null) app.stats.beats.rate(1) else null;
    return .{
        .avg = app.frame_budget.avg(),
        .peak = app.frame_budget.peak(),
        .fps_x10 = app.stats.fps_x10,
        .frames = if (r) |x| x.frames else null,
        .missed = if (r) |x| x.missed else null,
    };
}

/// Shift+F11: the budget page, opened straight from the game, or closed if it is showing.
pub fn toggle(app: *App) void {
    if (app.open and app.menu.page == .budget) {
        app.menu.page = .shelf; // F12 opens the shelf again, as before
        return app.setOpen(false);
    }
    app.menu.page = .budget;
    if (app.open) return app.redraw();
    app.setOpen(true);
}

/// The overlay's second line: "cart 0.69 FR 0.95 1.0p 99% m0/60", or "" before the probe spoke.
pub fn overlayLine(app: *const App, buf: *[map.OSD_COLS]u8) []const u8 {
    const s = app.frame_budget.avg() orelse return "";
    const r = app.stats.beats.rate(1);
    var t: [3][8]u8 = undefined;
    var w = std.Io.Writer.fixed(buf);
    w.print("cart {s} FR {s} {s}p {d}% m", .{
        budget.mcText(&t[0], s.cart), budget.mcText(&t[1], s.fresco), budget.planesText(&t[2], s.passes), budget.percent(s),
    }) catch {};
    if (r) |x| w.print("{d}/{d}", .{ x.missed, x.frames + x.missed }) catch {} else w.writeAll("-") catch {};
    return w.buffered();
}
