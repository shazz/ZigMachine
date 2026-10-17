// Shift+F12 reads the shelf again (app_shelf.zig) over a running cart: new disks are listed,
// the cart, the '*' mark, the cursor and the settings follow their FILES, not positions.
const std = @import("std");
const map = @import("map.zig");
const zmd = @import("zmd.zig");
const keymap = @import("keymap.zig");
const App = @import("app.zig").App;
const test_rig = @import("test_rig.zig");
const Rig = test_rig.Rig;
const press = test_rig.press;

const io = std.testing.io;

fn rescan(a: *App) void {
    a.key(keymap.KEY_LEFTSHIFT, 1);
    press(a, keymap.OSD_HOTKEY);
    a.key(keymap.KEY_LEFTSHIFT, 0);
}

fn addDisk(r: *Rig, file: []const u8, title: []const u8) !void {
    const disk = try zmd.testDisk(std.testing.allocator, title, &.{});
    defer std.testing.allocator.free(disk);
    try r.tmp.dir.writeFile(io, .{ .sub_path = file, .data = disk });
}

/// a.zmd loaded and running, the menu closed, the volume changed from its default.
fn running(r: *Rig) !App {
    var a = try r.app();
    a.menu.settings.volume = 77;
    press(&a, keymap.KEY_ENTER);
    try std.testing.expectEqual(@as(?usize, 0), a.current);
    return a;
}

test "Shift+F12 lists a disk copied since start, over the running cart" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    const resets = r.glass.resets;
    try addDisk(r, "0-new.zmd", "Uploaded"); // sorts first: every index moves
    rescan(&a);
    try std.testing.expectEqual(@as(usize, 3), a.disks.disks.len);
    try std.testing.expectEqualStrings("Uploaded", a.disks.titles[0]);
    try std.testing.expectEqualStrings("shelf: 3 carts", a.menu.status.?);
    try std.testing.expect(a.open and r.glass.ctrl & map.CTRL_OSD != 0); // shown in the menu
    try std.testing.expectEqual(resets, r.glass.resets); // the cart was not touched
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0);
    try std.testing.expectEqual(@as(?usize, 1), a.current); // a.zmd, now second
    try std.testing.expectEqual(@as(?usize, 1), a.menu.loaded);
    try std.testing.expectEqual(@as(usize, 1), a.menu.list.cursor);
    try std.testing.expectEqual(@as(u8, 77), a.menu.settings.volume);
    press(&a, keymap.OSD_HOTKEY); // plain F12 still toggles: closed over the cart
    try std.testing.expect(!a.open);
}

test "a disk that disappeared goes, unless its cart is the one running" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    press(&a, keymap.OSD_HOTKEY);
    press(&a, keymap.KEY_DOWN); // the cursor on b.zmd
    try r.tmp.dir.deleteFile(io, "b.zmd");
    try r.tmp.dir.deleteFile(io, "a.zmd"); // the running cart's disk too
    try addDisk(r, "c.zmd", "Cee");
    rescan(&a);
    try std.testing.expectEqual(@as(usize, 2), a.disks.disks.len);
    try std.testing.expectEqualStrings("c.zmd", a.disks.disks[0].file);
    try std.testing.expectEqualStrings("a.zmd", a.disks.disks[1].file); // kept: still in the window
    try std.testing.expectEqual(@as(?usize, 1), a.current);
    try std.testing.expectEqual(@as(usize, 1), a.menu.list.cursor); // b gone: clamped
    try std.testing.expectEqualStrings("shelf: 2 carts", a.menu.status.?);
    press(&a, keymap.KEY_ESC); // the menu still closes over the running cart
    try std.testing.expect(!a.open);
}
