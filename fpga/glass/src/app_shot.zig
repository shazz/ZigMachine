// "Take screenshot" (console > Take screenshot, PrintScreen anywhere, `glass ctl shot`): the
// picture the TV shows, as a PNG on the card in screenshots/ (Matt, 13 Nov: "so you can see what
// I see"). The worker copies it with the cart frozen for the copy only and encodes it
// (shot_worker.zig); tick() takes the file and writes it with the card made writable for the
// write and the rename only, as wifi.conf and glass.cfg are (app_wifi.writeCard). What happened
// shows in the menu's status line, or, with the menu closed, as a toast (app_stats.toast).
const std = @import("std");
const App = @import("app.zig").App;
const wk = @import("shot_worker.zig");
const file = @import("shot_file.zig");
const overlay = @import("app_stats.zig");

pub const State = struct {
    box: ?*wk.Worker = null, // made at the first shot: kept off the App
    nap: *const fn (u32) void = @import("wifi_worker.zig").napMs, // a test's fake firmware
    freeze_ms: u32 = 2000,

    pub fn busy(self: *const State) bool {
        return if (self.box) |w| w.busy() else false;
    }
};

fn worker(app: *App) ?*wk.Worker {
    if (app.shot.box) |w| return w;
    const w = app.gpa.create(wk.Worker) catch return null;
    w.* = .{ .gpa = app.gpa, .env = .{ .ddr = app.ddr, .nap = app.shot.nap, .freeze_ms = app.shot.freeze_ms, .clock = app.clock } };
    app.shot.box = w;
    return w;
}

pub fn deinit(app: *App) void {
    const w = app.shot.box orelse return;
    w.deinit();
    app.gpa.destroy(w);
    app.shot.box = null;
}

/// Start a shot; false (and said) when none could start.
pub fn take(app: *App) bool {
    if (!app.running) return fail(app, "screenshot: no cart running", .{});
    const w = worker(app) orelse return fail(app, "screenshot: out of memory", .{});
    w.start(@import("mouse.zig").deskMode(app.ddr)) catch |e|
        return fail(app, "screenshot: {s}", .{if (e == error.Busy) "busy, wait" else "no thread"});
    if (app.open) say(app, "screenshot...", .{});
    return true;
}

/// From App.tick, the OSD open or not: a finished shot onto the card.
pub fn tick(app: *App) void {
    const w = app.shot.box orelse return;
    switch (w.poll() orelse return) {
        .fail => |e| say(app, "screenshot: {s}", .{grabText(e)}),
        .png => |png| {
            defer app.gpa.free(png);
            save(app, png, w.frozen_ms);
        },
    }
}

fn save(app: *App, png: []const u8, frozen_ms: i64) void {
    if (!writable(app, true)) return say(app, "not saved: card read-only", .{});
    const n = file.save(app.io, app.card_dir, png);
    _ = writable(app, false);
    const num = n catch |e| return say(app, "not saved: {s}", .{fileText(e)});
    std.log.info("screenshot: {s}/{s}, {d} bytes, the cart held {d} ms", .{ file.DIR, &file.name(num, "PNG"), png.len, frozen_ms });
    say(app, "Saved {s}/{s}", .{ file.DIR, &file.name(num, "PNG") });
}

/// The card made writable for one change (null sd_writable: a test's directory, always writable).
fn writable(app: *App, rw: bool) bool {
    return if (app.sd_writable) |f| f(rw) else true;
}

fn grabText(e: wk.Fail) []const u8 {
    return switch (e) {
        error.NoMailbox => "old firmware", // "screenshot: " + these fit the 32-cell status row
        error.BadMailbox => "bad mailbox",
        error.FreezeTimeout => "cart did not stop",
        error.OutOfMemory => "out of memory",
        error.BadImage, error.WriteFailed, error.NoThread => "encode failed",
    };
}

fn fileText(e: file.Error) []const u8 {
    return switch (e) {
        error.NoCard => "no card",
        error.Full => "screenshots/ full",
        error.ReadOnly => "card read-only",
        error.CardFull => "card full",
        error.WriteFailed => "write failed",
    };
}

fn say(app: *App, comptime fmt: []const u8, args: anytype) void {
    app.menu.setStatus(fmt, args);
    if (app.open) return app.redraw();
    overlay.toast(app, app.menu.status orelse "");
}

fn fail(app: *App, comptime fmt: []const u8, args: anytype) bool {
    say(app, fmt, args);
    return false;
}
