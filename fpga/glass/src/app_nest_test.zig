// Nested folders end to end on the simulated glass (shelf.zig, shelf_view.zig, app_shelf.zig):
// the rig's a.zmd moved to demos/atari_st/, b.zmd to demos/. The OSD walks down two levels and
// boots it, the control channel loads it by any of its names, and a rescan that empties the
// platform folder sends the menu up ONE level, to demos/, which still holds b.zmd.
const std = @import("std");
const keymap = @import("keymap.zig");
const app_ctl = @import("app_ctl.zig");
const App = @import("app.zig").App;
const test_rig = @import("test_rig.zig");
const press = test_rig.press;

const gpa = std.testing.allocator;
const io = std.testing.io;

fn move(r: *test_rig.Rig, from: []const u8, to: []const u8) !void {
    const disk = try r.tmp.dir.readFileAlloc(io, from, gpa, .limited(1 << 20));
    defer gpa.free(disk);
    try r.tmp.dir.createDirPath(io, std.fs.path.dirname(to).?);
    try r.tmp.dir.writeFile(io, .{ .sub_path = to, .data = disk });
    try r.tmp.dir.deleteFile(io, from);
}

fn nestRig() !*test_rig.Rig {
    const r = try test_rig.Rig.init();
    errdefer r.deinit();
    try move(r, "a.zmd", "demos/atari_st/a.zmd");
    try move(r, "b.zmd", "demos/b.zmd");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "shelf.txt", .data = "demos/atari_st/a.zmd\tFAT DISK\tThe Group\t1990\n" });
    return r;
}

fn ctl(a: *App, line: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    app_ctl.exec(a, line, &w);
    return w.buffered();
}

test "the OSD goes down demos/ then atari_st/ and boots the cart there; Left comes up one" {
    const r = try nestRig();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    try std.testing.expectEqualStrings("demos/atari_st", a.disks.disks[0].folder);
    try std.testing.expectEqualStrings("FAT DISK", a.disks.disks[0].title); // shelf.txt by its nested path
    press(&a, keymap.KEY_ENTER); // demos/
    press(&a, keymap.KEY_ENTER); // atari_st/, the first row after ..
    try std.testing.expectEqualStrings("demos/atari_st", a.menu.list.folder());
    press(&a, keymap.KEY_LEFT);
    try std.testing.expectEqualStrings("demos", a.menu.list.folder());
    try std.testing.expectEqual(@as(usize, 1), a.menu.list.cursor); // on atari_st/
    press(&a, keymap.KEY_ENTER);
    press(&a, keymap.KEY_ENTER); // its cart
    try std.testing.expectEqual(@as(?usize, 0), a.current);
    try std.testing.expect(a.running and !a.open);
}

test "ctl load takes a nested disk's bare name or path; another folder is an err" {
    const r = try nestRig();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    var buf: [512]u8 = undefined;
    try std.testing.expectStringStartsWith(ctl(&a, "list", &buf), "a.zmd\tFAT DISK\tdemos/atari_st\nb.zmd\tWasm Only\tdemos\nok 2 disks");
    try std.testing.expectStringStartsWith(ctl(&a, "load demos/amiga/a.zmd", &buf), "err no disk demos/amiga/a.zmd");
    try std.testing.expectStringStartsWith(ctl(&a, "load demos/atari_st/a.zmd", &buf), "ok a.zmd running");
    try std.testing.expectStringStartsWith(ctl(&a, "load atari_st/a.zmd", &buf), "ok a.zmd running");
    try std.testing.expectStringStartsWith(ctl(&a, "load a.zmd", &buf), "ok a.zmd running");
}

test "a rescan that empties a nested folder sends the menu up one level, the cursor kept in range" {
    const r = try nestRig();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    press(&a, keymap.KEY_ENTER); // into demos/atari_st/, booting nothing
    try r.tmp.dir.deleteFile(io, "demos/atari_st/a.zmd");
    a.key(keymap.KEY_LEFTSHIFT, 1);
    press(&a, keymap.OSD_HOTKEY); // Shift+F12: read the shelf again
    a.key(keymap.KEY_LEFTSHIFT, 0);
    try std.testing.expectEqual(@as(usize, 1), a.disks.disks.len);
    try std.testing.expectEqualStrings("demos", a.menu.list.folder()); // b.zmd keeps demos/ alive
    try std.testing.expectEqual(@as(usize, 1), a.menu.list.cursor); // b.zmd, the row after ..
    try r.tmp.dir.deleteFile(io, "demos/b.zmd");
    a.key(keymap.KEY_LEFTSHIFT, 1);
    press(&a, keymap.OSD_HOTKEY);
    a.key(keymap.KEY_LEFTSHIFT, 0);
    try std.testing.expectEqualStrings("", a.menu.list.folder()); // nothing left: the top
    try std.testing.expectEqual(@as(usize, 0), a.menu.list.cursor);
}
