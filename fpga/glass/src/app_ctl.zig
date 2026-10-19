// What a control-channel command (ctl.zig) does to the console: the same paths the OSD
// and the keyboard take (docs/FPGA_GLASS.md, "The control channel"), so a script on the
// serial console drives exactly what Matt drives. Every reply ends in a line starting
// `ok` or `err` (`stats` replies with its ZMSTAT line, `list` with a line a disk first).
const std = @import("std");
const map = @import("map.zig");
const ctl = @import("ctl.zig");
const cart = @import("app_cart.zig");
const loader = @import("loader.zig");
const request = @import("app_request.zig");
const snd_info = @import("snd_info.zig");
const zmstat = @import("zmstat.zig");
const vstat = @import("vstat.zig");
const App = @import("app.zig").App;

/// How long a `tap` holds its key: past a cart's next frame, so a cart that polls
/// "held" sees it as well as one that takes key events.
pub const TAP_MS = 100;

/// The app's control-channel state: a tapped key waiting for its release.
pub const State = struct { up: ?u32 = null, up_at: i64 = 0 };

/// One command line: run it, write the reply.
pub fn exec(app: *App, line: []const u8, w: *std.Io.Writer) void {
    const cmd = ctl.parse(line) catch |err| return reply(w, "err {t} (try `help`)\n", .{err});
    switch (cmd) {
        .load => |l| load(app, l.file, l.program, w),
        .key => |k| key(app, k.code, k.mode, w),
        .joy => |bits| joy(app, bits, w),
        .stats => |secs| writeStats(app, secs, w),
        .osd => |open| osd(app, open, w),
        .quit_cart => quit(app, w),
        .list => list(app, w),
        .help => reply(w, ctl.HELP ++ "ok\n", .{}),
    }
}

/// From App.tick: the release of a tapped key, once it was held TAP_MS.
pub fn tick(app: *App) void {
    const up = app.ctl.up orelse return;
    if (app.clock() < app.ctl.up_at) return;
    app.ctl.up = null;
    app.keyEvent(up);
}

fn reply(w: *std.Io.Writer, comptime fmt: []const u8, args: anytype) void {
    w.print(fmt, args) catch {}; // a reply longer than the buffer is cut, never fatal
}

fn find(app: *App, file: []const u8) ?usize {
    for (app.disks.disks, 0..) |d, i| if (std.mem.eql(u8, d.file, file)) return i;
    for (app.disks.disks, 0..) |d, i| if (std.ascii.eqlIgnoreCase(d.file, file)) return i;
    return null;
}

fn load(app: *App, file: []const u8, program: ?[]const u8, w: *std.Io.Writer) void {
    if (find(app, file) == null) @import("app_shelf.zig").rescan(app); // copied since start-up?
    const i = find(app, file) orelse return reply(w, "err no disk {s} on the shelf (try `list`)\n", .{file});
    if (program) |name| return runProgram(app, i, name, w);
    cart.load(app, i);
    const name = app.disks.disks[i].file;
    if (app.current != i) return reply(w, "err {s}: {t}\n", .{ name, app.stats.last_err orelse error.NotLoaded });
    reply(w, "ok {s} running, loaded in {d} ms\n", .{ name, app.stats.last_load_ms });
}

/// A program off disk `i`, as GEM over it would ask for (app_request.zig): its fat disk
/// from <shelf>/progs/, the data disk in DDR beside it.
fn runProgram(app: *App, i: usize, name: []const u8, w: *std.Io.Writer) void {
    request.runProgram(app, i, name) catch |err| {
        app.stats.failed(err);
        return reply(w, "err {s} {s}: {t}\n", .{ app.disks.disks[i].file, name, err });
    };
    app.current = i;
    app.menu.loaded = i;
    if (app.open) app.setOpen(false);
    reply(w, "ok {s} {s} running, loaded in {d} ms\n", .{ app.disks.disks[i].file, name, app.stats.last_load_ms });
}

fn key(app: *App, code: u32, mode: ctl.KeyMode, w: *std.Io.Writer) void {
    if (app.ctl.up) |up| { // a tap still held: let it go first, in order
        app.ctl.up = null;
        app.keyEvent(up);
    }
    if (mode != .up) app.keyEvent(code | map.KEY_DOWN);
    switch (mode) {
        .down => {},
        .up => app.keyEvent(code),
        .tap => app.ctl = .{ .up = code, .up_at = app.clock() + TAP_MS },
    }
    reply(w, "ok key 0x{X} {t} to the {s}\n", .{ code, mode, if (app.open) "menu" else "cart" });
}

fn joy(app: *App, bits: u32, w: *std.Io.Writer) void {
    if (app.open) return reply(w, "err the menu is open: the cart gets no input (osd close)\n", .{});
    app.regs.write(map.REG_JOY, bits);
    reply(w, "ok joy 0x{X}\n", .{bits});
}

fn osd(app: *App, open: bool, w: *std.Io.Writer) void {
    if (open == app.open) return reply(w, "ok the menu is already {s}\n", .{if (open) "open" else "closed"});
    if (!open and app.current == null) return reply(w, "err no cart to go back to\n", .{});
    app.setOpen(open);
    reply(w, "ok menu {s}\n", .{if (open) "open" else "closed"});
}

fn quit(app: *App, w: *std.Io.Writer) void {
    loader.hold(app.regs) catch |err| return reply(w, "err {t}: the cart CPU did not stop\n", .{err});
    const was = app.current;
    app.current = null;
    app.stats.stop = .quit;
    app.menu.setStatus("cart stopped (control channel)", .{});
    app.setOpen(true);
    reply(w, "ok {s} stopped\n", .{if (was) |i| app.disks.disks[i].file else "nothing"});
}

fn list(app: *App, w: *std.Io.Writer) void {
    for (app.disks.disks) |d| reply(w, "{s}\t{s}\n", .{ d.file, d.title });
    reply(w, "ok {d} disks\n", .{app.disks.disks.len});
}

pub fn statLine(app: *App, secs: u32) zmstat.Line {
    const now = app.clock();
    const shown = app.current orelse app.menu.loaded;
    return .{
        .cart = if (shown) |i| app.disks.disks[i].file else "-",
        .state = zmstat.state(app.current != null, app.regs.read(map.REG_CART_STATE), app.stats.beats.stillMs(now), &app.stats),
        .secs = secs,
        .rate = if (app.current != null) app.stats.beats.rate(secs) else null,
        .snd = if (app.current != null) snd_info.read(app.ddr) else .{},
        .beat = app.regs.read(map.REG_CART_BEAT),
        .trap = app.stats.last_trap,
        .err = app.stats.last_err,
        .vs = if (app.current != null) vstat.read(app.ddr) else .{},
    };
}

fn writeStats(app: *App, secs: u32, w: *std.Io.Writer) void {
    const l = statLine(app, secs);
    zmstat.write(w, &l) catch {};
}
