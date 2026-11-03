// The shelf's folders in the menu (shelf_view.zig, page_shelf.zig, menu.zig): folders first,
// Enter opens one, ".." / Left / Backspace come back, a cart's row loads its DISK index, and a
// flat card lists exactly as before the folders.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const shelf = @import("shelf.zig");
const menu = @import("menu.zig");
const sv = @import("shelf_view.zig");
const View = @import("page_debug.zig").View;
const BView = @import("page_budget.zig").View;
const Action = menu.Action;

fn down(code: u32) u32 {
    return code | map.KEY_DOWN;
}

fn body(o: *const osd.Osd, r: u32) []const u8 {
    const S = struct {
        var buf: [osd.COLS]u8 = undefined;
    };
    for (&S.buf, 0..) |*c, i| c.* = @truncate(o.text[r * osd.COLS + i]);
    return std.mem.trimEnd(u8, S.buf[osd.BODY_COL..], " ");
}

fn rowText(o: *const osd.Osd, r: u32) []const u8 {
    const S = struct {
        var buf: [osd.COLS]u8 = undefined;
    };
    for (&S.buf, 0..) |*c, i| c.* = @truncate(o.text[r * osd.COLS + i]);
    return std.mem.trimEnd(u8, &S.buf, " ");
}

// Sorted by title, as shelf.scan leaves them: a flat disk, then carts in two folders.
const disks = [_]shelf.Disk{
    .{ .file = "demo-a.zmd", .title = "ALPHA", .folder = "games" },
    .{ .file = "demo-b.zmd", .title = "BRAVO", .folder = "demos" },
    .{ .file = "demo-c.zmd", .title = "CHARLIE" },
    .{ .file = "demo-d.zmd", .title = "DELTA", .folder = "demos" },
};

test "the top lists the folders in order, then the flat disks; a folder lists .. then its carts" {
    const top = sv.View{ .disks = &disks };
    try std.testing.expectEqual(@as(usize, 3), top.len());
    try std.testing.expectEqualStrings("demos", top.at(0).?.folder);
    try std.testing.expectEqualStrings("games", top.at(1).?.folder);
    try std.testing.expectEqual(sv.Row{ .disk = 2 }, top.at(2).?);
    try std.testing.expectEqual(@as(?sv.Row, null), top.at(3));
    const demos = sv.View{ .disks = &disks, .folder = "demos" };
    try std.testing.expectEqual(@as(usize, 3), demos.len());
    try std.testing.expectEqual(sv.Row.up, demos.at(0).?);
    try std.testing.expectEqual(sv.Row{ .disk = 3 }, demos.at(2).?);
    try std.testing.expectEqual(@as(?usize, 2), demos.rowOfDisk(3));
    try std.testing.expectEqual(@as(?usize, null), demos.rowOfDisk(0)); // in games/, not here
    try std.testing.expectEqual(@as(?usize, 1), top.rowOfFolder("games"));
    try std.testing.expectEqual(@as(?usize, null), top.rowOfFolder("tools")); // no such folder
    const flat = [_]shelf.Disk{ .{ .file = "x.zmd", .title = "X" }, .{ .file = "y.zmd", .title = "Y" } };
    const legacy = sv.View{ .disks = &flat };
    try std.testing.expectEqual(@as(usize, 2), legacy.len()); // an old card: row = disk, no folder rows
    try std.testing.expectEqual(sv.Row{ .disk = 1 }, legacy.at(1).?);
}

test "Enter opens a folder, loads a cart by its disk index, and .. Left Backspace come back" {
    var m = menu.Menu{ .disks = &disks };
    try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ENTER))); // into demos/
    try std.testing.expectEqualStrings("demos", m.list.folder());
    try std.testing.expectEqual(@as(usize, 1), m.list.cursor); // on its first cart, not on ..
    _ = m.key(down(map.KEY_ARROW_DOWN));
    try std.testing.expectEqual(Action{ .load = 3 }, m.key(down(map.KEY_ENTER))); // DELTA is disk 3
    try std.testing.expectEqual(Action{ .insert = 3 }, m.key(down('i')));
    _ = m.key(down(map.KEY_ARROW_LEFT));
    try std.testing.expectEqualStrings("", m.list.folder());
    try std.testing.expectEqual(@as(usize, 0), m.list.cursor); // back on demos/
    _ = m.key(down(map.KEY_ARROW_DOWN));
    _ = m.key(down(' ')); // into games/
    try std.testing.expectEqualStrings("games", m.list.folder());
    _ = m.key(down(map.KEY_BACKSPACE));
    try std.testing.expectEqual(@as(usize, 1), m.list.cursor); // back on games/
    _ = m.key(down(map.KEY_ENTER));
    _ = m.key(down(map.KEY_ARROW_UP)); // onto ..
    try std.testing.expectEqual(Action.none, m.key(down('i'))); // .. is no disk to insert
    try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ENTER)));
    try std.testing.expectEqualStrings("", m.list.folder());
    try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ARROW_LEFT))); // the top: nowhere to go
    try std.testing.expectEqual(@as(usize, 1), m.list.cursor);
}

test "the OSD shows folders with their cart count and marks, the folder in the title" {
    var m = menu.Menu{ .disks = &disks, .loaded = 3, .drive = 0 };
    var o = osd.Osd{};
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings(" ZIGMACHINE  SHELF     1/3   >", rowText(&o, 0));
    try std.testing.expectEqualStrings("* DEMOS/                     2", body(&o, 1)); // DELTA is loaded
    try std.testing.expectEqualStrings("A GAMES/                     1", body(&o, 2)); // ALPHA is in A
    try std.testing.expectEqualStrings("  CHARLIE", body(&o, 3));
    try std.testing.expectEqualStrings("folder demos: 2 carts", body(&o, 11));
    _ = m.key(down(map.KEY_ENTER));
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings(" ZIGMACHINE DEMOS       2/3   >", rowText(&o, 0));
    try std.testing.expectEqualStrings("  ..", body(&o, 1));
    try std.testing.expectEqualStrings("  BRAVO", body(&o, 2));
    try std.testing.expectEqualStrings("* DELTA", body(&o, 3));
    try std.testing.expectEqualStrings("no shelf.txt entry", body(&o, 11));
}

test "a name from outside finds its disk bare, by its folder path, or flat on an old card" {
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "demo-d.zmd"));
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "demos/demo-d.zmd"));
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "zigmachine/DEMOS/DEMO-D.ZMD"));
    try std.testing.expectEqual(@as(?usize, 2), sv.find(&disks, "demos/demo-c.zmd")); // flat: an old card
    try std.testing.expectEqual(@as(?usize, null), sv.find(&disks, "games/demo-d.zmd")); // the wrong folder
    try std.testing.expectEqual(@as(?usize, null), sv.find(&disks, "demo-z.zmd"));
    try std.testing.expectEqual(@as(?usize, null), sv.find(&disks, ""));
}
