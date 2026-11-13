// The Wi-Fi page's jobs (page_wifi.zig asks, wifi_job.zig does): started from a key, run on the
// worker's thread, their results picked up by tick() and shown. The card is the main thread's
// alone: wifi.conf is written here after a join worked (and removed by Forget), with the card
// made writable only for that, as a glass.cfg save is (app_cart.saveSettings).
const std = @import("std");
const App = @import("app.zig").App;
const wc = @import("wifi_conf.zig");
const cmd = @import("wifi_cmd.zig");
const job = @import("wifi_job.zig");
const wk = @import("wifi_worker.zig");
const pw = @import("page_wifi.zig");

const Box = struct { worker: wk.Worker, spawn: wk.Spawn };

pub const State = struct {
    box: ?*Box = null, // made at the first job: the worker's 64 KiB stay off the App
    env: ?job.Env = null, // a test's tools (wifi_fake.zig); null: the board's
    path_env: []const u8 = cmd.DEFAULT_PATH, // the process's PATH (main.zig)

    pub fn busy(self: *const State) bool {
        return if (self.box) |b| b.worker.busy() else false;
    }
};

fn worker(app: *App) ?*wk.Worker {
    if (app.wifi.box) |b| return &b.worker;
    const b = app.gpa.create(Box) catch return null;
    b.spawn = .{ .gpa = app.gpa, .io = app.io, .path_env = app.wifi.path_env };
    b.worker = .{ .env = app.wifi.env orelse .{
        .io = app.io,
        .runner = b.spawn.runner(),
        .card_dir = app.sys_dir,
        .nap = wk.napMs,
        .path_env = app.wifi.path_env,
    } };
    app.wifi.box = b;
    return &b.worker;
}

pub fn deinit(app: *App) void {
    const b = app.wifi.box orelse return;
    b.worker.deinit();
    app.gpa.destroy(b);
    app.wifi.box = null;
}

/// menu.Action.wifi: the job the page asked for.
pub fn act(app: *App, what: pw.Cmd) void {
    const page = &app.menu.wifi;
    var req = job.Request{ .kind = what };
    defer std.crypto.secureZero(u8, &req.pass);
    switch (what) {
        .status => page.info.saved = loadSaved(app),
        .scan => {},
        .forget => if (!forgetSaved(app)) return,
        .join => {
            const net = page.picked() orelse return;
            req.ssid = net.ssid;
            req.open = !net.secured;
            @memcpy(req.pass[0..page.pass_len], page.passText());
            req.pass_len = page.pass_len;
            page.clearPass();
        },
    }
    const w = worker(app) orelse return app.menu.setStatus("Wi-Fi: out of memory", .{});
    w.start(&req) catch |err| return app.menu.setStatus("Wi-Fi: {s}", .{if (err == error.Busy) "busy, wait" else "no thread"});
    if (what != .status) page.wait(what);
}

/// From App.tick, the OSD open or not: a finished job's result into the page.
pub fn tick(app: *App) void {
    const b = app.wifi.box orelse return;
    const res = b.worker.poll() orelse return;
    defer std.crypto.secureZero(u8, &res.conf_buf); // the hashed key: gone once saved
    show(app, res);
    if (app.open and app.menu.page == .wifi) app.redraw();
}

fn show(app: *App, res: *const job.Result) void {
    const page = &app.menu.wifi;
    const i = &page.info;
    i.* = .{ .known = true, .fail = res.fail, .missing = res.missing, .connected = res.connected, .ip_len = res.ip_len, .saved = i.saved };
    @memcpy(i.ip_buf[0..res.ip_len], res.ip());
    const was_busy = page.screen == .busy;
    if (res.kind == .scan and res.fail == .none) {
        page.n_nets = res.n_nets;
        @memcpy(page.nets[0..res.n_nets], res.nets[0..res.n_nets]);
        page.pick = 0;
        page.top = 0;
        if (was_busy) page.screen = .list;
        if (res.n_nets == 0) return app.menu.setStatus("no networks found", .{});
        return app.menu.setStatus("{d} networks", .{res.n_nets});
    }
    if (was_busy) page.screen = if (res.fail == .wrong_key) .password else .home;
    if (res.fail != .none) return failed(app, res);
    if (res.kind == .join) joined(app, res);
}

fn failed(app: *App, res: *const job.Result) void {
    const m = &app.menu;
    switch (res.fail) {
        .none => {},
        .no_tools => m.setStatus("Wi-Fi tools not found: {s}", .{if (res.missing) |t| @tagName(t) else "?"}),
        .no_iface => m.setStatus("no Wi-Fi dongle (no wlan0)", .{}),
        .scan_failed => m.setStatus("scan failed: try again", .{}),
        .bad_pass => m.setStatus("password: 8 to 63 characters", .{}),
        .conf_write => m.setStatus("cannot write /tmp/wifi", .{}),
        .supplicant => m.setStatus("wpa_supplicant did not start", .{}),
        .wrong_key => m.setStatus("wrong password", .{}),
        .not_found => m.setStatus("network not found", .{}),
        .timeout => m.setStatus("no answer: timed out", .{}),
        .no_address => m.setStatus("joined, no address (DHCP)", .{}),
    }
    std.log.warn("wifi {t}: {t}", .{ res.kind, res.fail });
}

/// Associated with an address: now the card names this network, for the next boot (S99wifi).
fn joined(app: *App, res: *const job.Result) void {
    writeCard(app, res.conf()) catch |err| {
        std.log.warn("{s}: {t}", .{ wc.FILE, err });
        return app.menu.setStatus("joined; not saved: {s}", .{if (err == error.ReadOnly) "card read-only" else @errorName(err)});
    };
    app.menu.wifi.info.saved = loadSaved(app);
    app.menu.setStatus("joined, saved to {s}", .{wc.FILE});
}

/// The card made writable for one change (null sd_writable: a test's directory, always writable).
fn writable(app: *App, rw: bool) bool {
    return if (app.sd_writable) |f| f(rw) else true;
}

fn writeCard(app: *App, text: []const u8) !void {
    if (!writable(app, true)) return error.ReadOnly;
    defer _ = writable(app, false);
    try wc.save(app.io, app.sys_dir, text);
}

fn removeCard(app: *App) !void {
    if (!writable(app, true)) return error.ReadOnly;
    defer _ = writable(app, false);
    try wc.remove(app.io, app.sys_dir);
}

/// wifi.conf off the card; false (and said) when the card would not let go of it.
fn forgetSaved(app: *App) bool {
    removeCard(app) catch |err| {
        app.menu.setStatus("not forgotten: {s}", .{if (err == error.ReadOnly) "card read-only" else @errorName(err)});
        return false;
    };
    app.menu.wifi.info.saved = null;
    app.menu.setStatus("forgotten", .{});
    return true;
}

fn loadSaved(app: *App) ?wc.Saved {
    var buf: [wc.MAX_BYTES]u8 = undefined;
    return wc.load(app.io, app.sys_dir, &buf);
}
