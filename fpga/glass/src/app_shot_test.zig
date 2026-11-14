// "Take screenshot" driven as Matt drives it (app_shot.zig): PrintScreen with the menu closed (a
// toast says where it went), the console's item with it open (the status line), and every way it
// fails: no cart, a firmware that does not stop, a shot already under way, a read-only card, a
// write the card refuses. The rig's window carries a mailbox and a tiny picture (shot_grab_test).
const std = @import("std");
const map = @import("map.zig");
const keymap = @import("keymap.zig");
const test_rig = @import("test_rig.zig");
const gt = @import("shot_grab_test.zig");
const App = @import("app.zig").App;
const Rig = test_rig.Rig;
const press = test_rig.press;

const io = std.testing.io;
const PIC = 1000; // the front picture's word offset in the rig's window: 8 x 2

fn running(r: *Rig) !App {
    var a = try r.app();
    press(&a, keymap.KEY_ENTER); // a.zmd boots: the window is rewritten, then the firmware's mailbox
    try std.testing.expect(a.running);
    _ = gt.mailbox(&r.words, PIC, PIC, 8, 2);
    for (r.words[PIC..][0..16], 0..) |*w, i| w.* = @intCast(i / 2 * 0x10101); // low res: column pairs
    a.shot.nap = gt.Fw.nap;
    a.shot.freeze_ms = 50;
    return a;
}

/// Ticks until the shot under way is done and handled.
fn settle(a: *App) void {
    while (a.shot.busy()) {
        a.tick();
        std.Thread.yield() catch {};
    }
}

fn status(a: *const App) []const u8 {
    return a.menu.status orelse "";
}

fn saved(r: *Rig, name: []const u8) ![]u8 {
    var dir = try r.tmp.dir.openDir(io, "screenshots", .{});
    defer dir.close(io);
    return dir.readFileAlloc(io, name, std.testing.allocator, .limited(1 << 20));
}

test "PrintScreen with the menu closed: SHOT0001.PNG of the picture, and a toast that says so" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    try std.testing.expect(!a.open);
    press(&a, keymap.SHOT_HOTKEY);
    settle(&a);
    try std.testing.expectEqualStrings("Saved screenshots/SHOT0001.PNG", status(&a));
    try std.testing.expectEqualStrings("Saved screenshots/SHOT0001.PNG", a.toast.buf[0..a.toast.len]);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD_STATS != 0); // the corner window shows it
    const png = try saved(r, "SHOT0001.PNG");
    defer std.testing.allocator.free(png);
    try std.testing.expectEqualStrings("\x89PNG", png[0..4]);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, png[16..20], .big)); // 8 columns undoubled
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, png[20..24], .big));
    for (0..@import("app_stats.zig").TOAST_TICKS) |_| a.tick();
    try std.testing.expectEqual(@as(usize, 0), a.toast.len); // gone after its time, the window with it
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
}

test "the console's Take screenshot: the menu stays, the next number, said on the status line" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    try r.tmp.dir.createDirPath(io, "screenshots");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "screenshots/SHOT0006.PNG", .data = "older" });
    press(&a, keymap.OSD_HOTKEY);
    a.menu.page = .console;
    a.menu.console.cursor = 7; // Take screenshot
    press(&a, keymap.KEY_ENTER);
    try std.testing.expectEqualStrings("screenshot...", status(&a));
    settle(&a);
    try std.testing.expect(a.open);
    try std.testing.expectEqualStrings("Saved screenshots/SHOT0007.PNG", status(&a));
    const png = try saved(r, "SHOT0007.PNG");
    std.testing.allocator.free(png);
}

test "no cart, a firmware that never stops, a shot under way: each said, nothing written" {
    const r = try Rig.init();
    defer r.deinit();
    var idle = try r.app();
    defer idle.deinit();
    press(&idle, keymap.SHOT_HOTKEY);
    try std.testing.expectEqualStrings("screenshot: no cart running", status(&idle));
    var a = try running(r);
    defer a.deinit();
    gt.Fw.answers = false;
    press(&a, keymap.SHOT_HOTKEY);
    press(&a, keymap.SHOT_HOTKEY); // 50 ms of waiting for the freeze: still under way
    try std.testing.expectEqualStrings("screenshot: busy, wait", status(&a));
    settle(&a);
    try std.testing.expectEqualStrings("screenshot: cart did not stop", status(&a));
    try std.testing.expectError(error.FileNotFound, r.tmp.dir.access(io, "screenshots", .{}));
}

fn readOnly(rw: bool) bool {
    return !rw; // the remount to rw fails; back to ro works
}

test "a read-only card, and a card that refuses the write: said, no file, no temp left" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    a.sd_writable = readOnly;
    press(&a, keymap.SHOT_HOTKEY);
    settle(&a);
    try std.testing.expectEqualStrings("not saved: card read-only", status(&a));
    try std.testing.expectError(error.FileNotFound, r.tmp.dir.access(io, "screenshots", .{}));
    a.sd_writable = null;
    try r.tmp.dir.writeFile(io, .{ .sub_path = "screenshots", .data = "a file where the folder goes" });
    press(&a, keymap.SHOT_HOTKEY);
    settle(&a);
    try std.testing.expectEqualStrings("not saved: write failed", status(&a));
}

fn ctl(a: *App, line: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    @import("app_ctl.zig").exec(a, line, &w);
    return w.buffered();
}

test "glass ctl shot: the lead's way in over ssh; refused with the reason when no cart runs" {
    const r = try Rig.init();
    defer r.deinit();
    var buf: [128]u8 = undefined;
    var idle = try r.app();
    defer idle.deinit();
    try std.testing.expectEqualStrings("err screenshot: no cart running\n", ctl(&idle, "shot", &buf));
    var a = try running(r);
    defer a.deinit();
    try std.testing.expect(std.mem.startsWith(u8, ctl(&a, "shot", &buf), "ok screenshot under way"));
    settle(&a);
    const png = try saved(r, "SHOT0001.PNG");
    std.testing.allocator.free(png);
}
