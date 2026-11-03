// A card with category folders, end to end on the simulated glass (shelf.zig, shelf_view.zig):
// the cart in demos/ loads from there by the OSD and by the control channel, by its bare
// name or its folder path, and a folder that empties under a rescan sends the menu back up.
const std = @import("std");
const map = @import("map.zig");
const keymap = @import("keymap.zig");
const app_ctl = @import("app_ctl.zig");
const App = @import("app.zig").App;
const test_rig = @import("test_rig.zig");
const press = test_rig.press;

const gpa = std.testing.allocator;
const io = std.testing.io;

/// The rig's a.zmd (the fat disk) moved into demos/; b.zmd stays flat.
fn folderRig() !*test_rig.Rig {
    const r = try test_rig.Rig.init();
    errdefer r.deinit();
    const disk = try r.tmp.dir.readFileAlloc(io, "a.zmd", gpa, .limited(1 << 20));
    defer gpa.free(disk);
    try r.tmp.dir.createDirPath(io, "demos");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "demos/a.zmd", .data = disk });
    try r.tmp.dir.deleteFile(io, "a.zmd");
    return r;
}

fn ctl(a: *App, line: []const u8, buf: []u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    app_ctl.exec(a, line, &w);
    return w.buffered();
}

test "the OSD opens demos/ and boots its cart from the folder" {
    const r = try folderRig();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    try std.testing.expectEqualStrings("demos", a.disks.disks[0].folder);
    press(&a, keymap.KEY_ENTER); // demos/, the top's first row
    try std.testing.expectEqualStrings("demos", a.menu.list.folder());
    try std.testing.expect(a.current == null);
    press(&a, keymap.KEY_ENTER); // its cart
    try std.testing.expectEqual(@as(?usize, 0), a.current);
    try std.testing.expect(a.running and !a.open);
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0);
}

test "ctl load takes the bare name or the folder path; the wrong folder is an err" {
    const r = try folderRig();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    var buf: [512]u8 = undefined;
    try std.testing.expectStringStartsWith(ctl(&a, "list", &buf), "a.zmd\tFat Disk\tdemos\nb.zmd\tWasm Only\t\nok 2 disks");
    try std.testing.expectStringStartsWith(ctl(&a, "load games/a.zmd", &buf), "err no disk games/a.zmd");
    try std.testing.expectStringStartsWith(ctl(&a, "load demos/a.zmd", &buf), "ok a.zmd running");
    try std.testing.expectStringStartsWith(ctl(&a, "load a.zmd", &buf), "ok a.zmd running");
}

test "a folder emptied under a rescan sends the menu back to the top" {
    const r = try folderRig();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER); // into demos/, not booting anything
    try r.tmp.dir.deleteFile(io, "demos/a.zmd");
    a.key(keymap.KEY_LEFTSHIFT, 1);
    press(&a, keymap.OSD_HOTKEY); // Shift+F12: read the shelf again
    a.key(keymap.KEY_LEFTSHIFT, 0);
    try std.testing.expectEqual(@as(usize, 1), a.disks.disks.len);
    try std.testing.expectEqualStrings("", a.menu.list.folder());
    try std.testing.expectEqual(@as(usize, 0), a.menu.list.cursor); // on b.zmd, the only row
    press(&a, keymap.KEY_LEFT); // the top: Left does nothing
    try std.testing.expect(a.open and a.current == null);
}
