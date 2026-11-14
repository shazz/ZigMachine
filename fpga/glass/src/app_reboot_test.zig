// "Reboot" (app_reboot.zig) driven as Matt and the lead's scripts drive it: the console's item with
// its Yes/No, and `glass ctl reboot`. The restart and the sync are fakes: the host is never rebooted.
const std = @import("std");
const map = @import("map.zig");
const keymap = @import("keymap.zig");
const app_ctl = @import("app_ctl.zig");
const test_rig = @import("test_rig.zig");
const page_console = @import("page_console.zig");
const App = @import("app.zig").App;
const Rig = test_rig.Rig;
const press = test_rig.press;

var syncs: u32 = 0;
var restarts: u32 = 0;
var order: [4]u8 = undefined;
var restart_result = true;

fn fakeSync() void {
    order[syncs + restarts] = 's';
    syncs += 1;
}

fn fakeRestart() bool {
    order[syncs + restarts] = 'r';
    restarts += 1;
    return restart_result;
}

var rw_calls: [4]bool = undefined;
var n_rw: usize = 0;

fn fakeRw(rw: bool) bool {
    rw_calls[n_rw] = rw;
    n_rw += 1;
    return true;
}

fn reset() void {
    syncs = 0;
    restarts = 0;
    n_rw = 0;
    restart_result = true;
}

fn rigged(r: *Rig) !App {
    reset();
    var a = try r.app();
    a.reboot.sync_fn = fakeSync;
    a.reboot.restart_fn = fakeRestart;
    a.sd_writable = fakeRw;
    press(&a, keymap.KEY_RIGHT); // the console page
    for (0..@intFromEnum(page_console.Item.reboot)) |_| press(&a, keymap.KEY_DOWN);
    return a;
}

fn status(a: *const App) []const u8 {
    return a.menu.status orelse "";
}

test "Enter then Enter: the default is No, nothing is synced or restarted, however many ticks" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigged(r);
    defer a.deinit();
    press(&a, keymap.KEY_ENTER); // the question
    try std.testing.expect(a.menu.console.ask);
    press(&a, keymap.KEY_ENTER); // No
    for (0..3) |_| a.tick();
    try std.testing.expectEqual(@as(u32, 0), syncs + restarts);
    try std.testing.expect(!a.reboot.pending);
    press(&a, keymap.KEY_ENTER);
    press(&a, keymap.KEY_ESC); // Esc: no, and the console page stays
    for (0..3) |_| a.tick();
    try std.testing.expectEqual(@as(u32, 0), syncs + restarts);
    try std.testing.expect(a.open);
}

test "Yes: Rebooting... shows, then the next tick syncs, makes the card read-only and restarts, in that order" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigged(r);
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    press(&a, keymap.KEY_DOWN); // Yes
    press(&a, keymap.KEY_ENTER);
    try std.testing.expectEqualStrings("Rebooting...", status(&a));
    try std.testing.expectEqual(@as(u32, 0), restarts); // not before the OSD had its say
    a.tick();
    try std.testing.expectEqualSlices(u8, "sr", order[0..2]);
    try std.testing.expectEqual(@as(u32, 1), restarts);
    try std.testing.expect(r.glass.audio_vol & map.AUDIO_MUTE != 0); // the mixer was silenced
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0); // and the cart CPU held
    try std.testing.expect(n_rw >= 1 and !rw_calls[n_rw - 1]); // the card's last word: read-only
    a.tick();
    try std.testing.expectEqual(@as(u32, 1), restarts); // once
}

test "a restart that returns says so and leaves the menu up" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigged(r);
    defer a.deinit();
    restart_result = false;
    press(&a, keymap.KEY_ENTER);
    press(&a, keymap.KEY_DOWN);
    press(&a, keymap.KEY_ENTER);
    a.tick();
    try std.testing.expectEqualStrings("reboot failed", status(&a));
    try std.testing.expect(a.open);
}

test "an unsaved volume is saved before the sync" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigged(r);
    defer a.deinit();
    a.settings_dirty = true;
    _ = @import("app_reboot.zig").request(&a);
    a.tick();
    try std.testing.expect(!a.settings_dirty);
    try std.testing.expect(!rw_calls[n_rw - 1] and rw_calls[0]); // rw for the write, ro at the end
}

fn run(a: *App, line: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    app_ctl.exec(a, line, &w);
    return w.buffered();
}

test "glass ctl reboot: ok first, the sync and restart on the next tick, no question; twice is an err" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigged(r);
    defer a.deinit();
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings("ok rebooting\n", run(&a, "reboot", &buf));
    try std.testing.expectEqual(@as(u32, 0), restarts);
    try std.testing.expect(std.mem.startsWith(u8, run(&a, "reboot", &buf), "err"));
    a.tick();
    try std.testing.expectEqual(@as(u32, 1), syncs);
    try std.testing.expectEqual(@as(u32, 1), restarts);
    try std.testing.expect(std.mem.startsWith(u8, run(&a, "reboot now", &buf), "err TooManyArguments"));
}
