// Nested folders in the menu (shelf_view.zig, page_shelf.zig, menu.zig): CARTS/demos/ holds a
// folder per platform (atari_st/, amiga/, ...) beside any disk lying in demos/ itself. A folder
// row opens its full path, ".." and Left go up ONE level onto the folder just left, the OSD
// names a folder by its last part with '_' as a space, and counts and marks run down the tree.
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

fn line(o: *const osd.Osd, r: u32, from: usize) []const u8 {
    const S = struct {
        var buf: [osd.COLS]u8 = undefined;
    };
    for (&S.buf, 0..) |*c, i| c.* = @truncate(o.text[r * osd.COLS + i]);
    return std.mem.trimEnd(u8, S.buf[from..], " ");
}

// Sorted by title, as shelf.scan leaves them.
const disks = [_]shelf.Disk{
    .{ .file = "demo-a.zmd", .title = "ALPHA", .folder = "demos/atari_st" },
    .{ .file = "demo-b.zmd", .title = "BRAVO", .folder = "demos/amiga" },
    .{ .file = "demo-c.zmd", .title = "CHARLIE", .folder = "demos" }, // a disk beside the platforms
    .{ .file = "demo-d.zmd", .title = "DELTA", .folder = "demos/atari_st" },
    .{ .file = "demo-e.zmd", .title = "ECHO", .folder = "games" },
};

test "each level lists .., its own folders, then its own disks; a folder row is its full path" {
    const top = sv.View{ .disks = &disks };
    try std.testing.expectEqual(@as(usize, 2), top.len()); // demos/, games/: no platform at the top
    try std.testing.expectEqualStrings("demos", top.at(0).?.folder);
    try std.testing.expectEqualStrings("games", top.at(1).?.folder);
    const demos = sv.View{ .disks = &disks, .folder = "demos" };
    try std.testing.expectEqual(@as(usize, 4), demos.len());
    try std.testing.expectEqual(sv.Row.up, demos.at(0).?);
    try std.testing.expectEqualStrings("demos/amiga", demos.at(1).?.folder);
    try std.testing.expectEqualStrings("demos/atari_st", demos.at(2).?.folder);
    try std.testing.expectEqual(sv.Row{ .disk = 2 }, demos.at(3).?);
    try std.testing.expectEqual(@as(?usize, 2), demos.rowOfFolder("demos/atari_st"));
    try std.testing.expectEqual(@as(?usize, null), top.rowOfFolder("demos/atari_st")); // not right under the top
    const st = sv.View{ .disks = &disks, .folder = "demos/atari_st" };
    try std.testing.expectEqual(@as(usize, 3), st.len());
    try std.testing.expectEqual(sv.Row{ .disk = 3 }, st.at(2).?);
    try std.testing.expectEqual(@as(?usize, null), st.rowOfDisk(2)); // CHARLIE is one level up
    try std.testing.expectEqual(@as(usize, 4), sv.count(&disks, "demos")); // the whole tree under it
    try std.testing.expectEqual(@as(usize, 1), sv.direct(&disks, "demos"));
    try std.testing.expect(!sv.within("demosx/a", "demos")); // a prefix is not a parent
    try std.testing.expectEqualStrings("demos", sv.parent("demos/atari_st"));
    try std.testing.expectEqualStrings("", sv.parent("demos"));
}

test "Enter goes down two levels, Left and .. come back ONE level onto the folder just left" {
    var m = menu.Menu{ .disks = &disks };
    _ = m.key(down(map.KEY_ENTER)); // demos/
    try std.testing.expectEqualStrings("demos", m.list.folder());
    try std.testing.expectEqual(@as(usize, 1), m.list.cursor); // on amiga/
    _ = m.key(down(map.KEY_ARROW_DOWN));
    _ = m.key(down(map.KEY_ENTER)); // atari_st/
    try std.testing.expectEqualStrings("demos/atari_st", m.list.folder());
    _ = m.key(down(map.KEY_ARROW_DOWN));
    try std.testing.expectEqual(Action{ .load = 3 }, m.key(down(map.KEY_ENTER))); // DELTA
    _ = m.key(down(map.KEY_ARROW_LEFT));
    try std.testing.expectEqualStrings("demos", m.list.folder()); // up one, not to the top
    try std.testing.expectEqual(@as(usize, 2), m.list.cursor); // on atari_st/
    _ = m.key(down(map.KEY_ARROW_UP));
    _ = m.key(down(map.KEY_ENTER)); // amiga/
    _ = m.key(down(map.KEY_ARROW_UP)); // onto ..
    _ = m.key(down(map.KEY_ENTER));
    try std.testing.expectEqualStrings("demos", m.list.folder());
    try std.testing.expectEqual(@as(usize, 1), m.list.cursor); // on amiga/
    _ = m.key(down(map.KEY_BACKSPACE));
    try std.testing.expectEqualStrings("", m.list.folder());
    try std.testing.expectEqual(@as(usize, 0), m.list.cursor); // on demos/
}

test "the OSD names a platform folder by its last part, '_' a space; counts and marks run down" {
    var m = menu.Menu{ .disks = &disks, .loaded = 3, .drive = 1 };
    var o = osd.Osd{};
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings("A DEMOS/                     4", line(&o, 1, osd.BODY_COL)); // BRAVO in A, 2 down
    m.list.enter("demos", &disks);
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings(" ZIGMACHINE DEMOS       2/4   >", line(&o, 0, 0));
    try std.testing.expectEqualStrings("  ..", line(&o, 1, osd.BODY_COL));
    try std.testing.expectEqualStrings("A AMIGA/                     1", line(&o, 2, osd.BODY_COL));
    try std.testing.expectEqualStrings("* ATARI ST/                  2", line(&o, 3, osd.BODY_COL));
    try std.testing.expectEqualStrings("  CHARLIE", line(&o, 4, osd.BODY_COL));
    try std.testing.expectEqualStrings("folder amiga: 1 carts", line(&o, 11, osd.BODY_COL));
    m.list.enter("demos/atari_st", &disks);
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings(" ZIGMACHINE ATARI ST    2/3   >", line(&o, 0, 0));
    try std.testing.expectEqualStrings("* DELTA", line(&o, 3, osd.BODY_COL));
}

test "a name from outside finds a nested disk bare, by its full path or its last folders" {
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "demo-d.zmd"));
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "demos/atari_st/demo-d.zmd"));
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "atari_st/demo-d.zmd"));
    try std.testing.expectEqual(@as(?usize, 3), sv.find(&disks, "CARTS/DEMOS/ATARI_ST/DEMO-D.ZMD"));
    try std.testing.expectEqual(@as(?usize, null), sv.find(&disks, "demos/demo-d.zmd")); // it is not there
    try std.testing.expectEqual(@as(?usize, null), sv.find(&disks, "st/demo-d.zmd")); // not a whole folder
    try std.testing.expectEqual(@as(?usize, null), sv.find(&disks, "demos/amiga/demo-d.zmd"));
    try std.testing.expectEqual(@as(?usize, 2), sv.find(&disks, "demos/demo-c.zmd"));
}
