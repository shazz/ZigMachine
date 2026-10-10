// The menu's three pages, as pure state and drawing (menu.zig).
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const shelf = @import("shelf.zig");
const menu = @import("menu.zig");
const page_shelf = @import("page_shelf.zig");
const page_console = @import("page_console.zig");
const View = @import("page_debug.zig").View;
const Action = menu.Action;

fn down(code: u32) u32 {
    return code | map.KEY_DOWN;
}

fn row(o: *const osd.Osd, r: u32) []const u8 {
    const S = struct {
        var buf: [osd.COLS]u8 = undefined;
    };
    for (&S.buf, 0..) |*c, i| c.* = @truncate(o.text[r * osd.COLS + i]);
    return std.mem.trimEnd(u8, &S.buf, " ");
}

fn disks(comptime titles: []const []const u8) [titles.len]shelf.Disk {
    var out: [titles.len]shelf.Disk = undefined;
    for (titles, &out) |t, *d| d.* = .{ .file = "x.zmd", .title = t };
    return out;
}

test "the shelf's cursor moves, scrolls and loads" {
    const d = disks(&.{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n" });
    var m = menu.Menu{ .disks = &d };
    for (0..13) |_| try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ARROW_DOWN)));
    try std.testing.expectEqual(@as(usize, 13), m.list.cursor);
    try std.testing.expectEqual(@as(usize, 13 + 1 - page_shelf.SHOWN), m.list.top);
    _ = m.key(down(map.KEY_ARROW_DOWN)); // already on the last disk
    try std.testing.expectEqual(Action{ .load = 13 }, m.key(down(map.KEY_ENTER)));
    try std.testing.expectEqual(Action.none, m.key(map.KEY_ENTER)); // a release does nothing
    try std.testing.expectEqual(Action.close, m.key(down(map.KEY_ESCAPE)));
    try std.testing.expectEqual(Action.cold, m.key(down('r')));
    try std.testing.expectEqual(Action.warm, m.key(down('W')));
    var empty = menu.Menu{ .disks = &.{} };
    try std.testing.expectEqual(Action.none, empty.key(down(map.KEY_ENTER)));
}

test "the shelf shows titles, the loaded mark, and the selected cart's details" {
    var d = disks(&.{ "UNION DEMO", "OXYGENE STNICCC 2000", "A TITLE FAR TOO LONG FOR THE OSD ROW" });
    d[1].meta = .{ .title = d[1].title, .group = "Oxygene", .year = "2000", .kind = "atari st", .desc = "The flat-shaded polygon flight, streamed off its own floppy, then again in fullscreen overscan at 400 by 280." };
    var m = menu.Menu{ .disks = &d, .loaded = 0 };
    m.list.cursor = 1;
    var o = osd.Osd{};
    m.draw(&o, &View{});
    try std.testing.expectEqualStrings(" ZIGMACHINE  SHELF     2/3   >", row(&o, 0));
    try std.testing.expectEqualStrings("*UNION DEMO", row(&o, page_shelf.FIRST));
    try std.testing.expect(o.text[(page_shelf.FIRST + 1) * osd.COLS] & map.OSD_INVERSE != 0);
    try std.testing.expectEqualStrings(" A TITLE FAR TOO LONG FOR THE O~", row(&o, page_shelf.FIRST + 2));
    try std.testing.expectEqualStrings("Oxygene 2000            atari st", row(&o, page_shelf.DETAIL));
    try std.testing.expectEqualStrings("The flat-shaded polygon flight,", row(&o, page_shelf.DETAIL + 1));
    try std.testing.expectEqualStrings("then again in fullscreen~", row(&o, page_shelf.DETAIL + 3)[0..25]);
    try std.testing.expectEqualStrings(menu.HINT, row(&o, osd.ROWS - 1));
    m.list.cursor = 2; // selected, the long title scrolls instead of being cut
    m.list.phase = 4;
    m.draw(&o, &View{});
    try std.testing.expectEqualStrings(" TITLE FAR TOO LONG FOR THE OSD", row(&o, page_shelf.FIRST + 2));
    try std.testing.expectEqualStrings("no shelf.txt entry", row(&o, page_shelf.DETAIL)); // an unknown cart
    try std.testing.expectEqualStrings("x.zmd", row(&o, page_shelf.DETAIL + 1));
}

test "the console page resets, changes the volume and mute, and goes back" {
    const d = disks(&.{"a"});
    var m = menu.Menu{ .disks = &d };
    try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ARROW_RIGHT)));
    try std.testing.expectEqual(menu.Page.console, m.page);
    try std.testing.expectEqual(Action.cold, m.key(down(map.KEY_ENTER)));
    _ = m.key(down(map.KEY_ARROW_DOWN));
    try std.testing.expectEqual(Action.warm, m.key(down(' ')));
    _ = m.key(down(map.KEY_ARROW_DOWN)); // Volume
    try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ARROW_RIGHT))); // already at the top
    try std.testing.expectEqual(Action.settings, m.key(down(map.KEY_ARROW_LEFT)));
    try std.testing.expectEqual(@as(u8, 255 - page_console.VOL_STEP), m.settings.volume);
    for (0..20) |_| _ = m.key(down(map.KEY_ARROW_LEFT) | map.KEY_REPEAT);
    try std.testing.expectEqual(@as(u8, 0), m.settings.volume);
    _ = m.key(down(map.KEY_ARROW_DOWN)); // Mute
    try std.testing.expectEqual(Action.settings, m.key(down(map.KEY_ENTER)));
    try std.testing.expect(m.settings.mute);
    var o = osd.Osd{};
    m.draw(&o, &View{});
    try std.testing.expectEqualStrings(" Volume  ----------------   0%", row(&o, page_console.FIRST + 2));
    try std.testing.expectEqualStrings(" Mute    on", row(&o, page_console.FIRST + 3));
    try std.testing.expectEqual(Action.save, m.key(down(map.KEY_ESCAPE)));
    try std.testing.expectEqual(menu.Page.shelf, m.page);
}

test "the debug page opens from the console and any back key leaves it" {
    const d = disks(&.{"a"});
    var m = menu.Menu{ .disks = &d, .page = .console };
    for (0..4) |_| _ = m.key(down(map.KEY_ARROW_DOWN)); // Debug...
    _ = m.key(down(map.KEY_ENTER));
    try std.testing.expectEqual(menu.Page.debug, m.page);
    try std.testing.expectEqual(Action.none, m.key(down('x')));
    try std.testing.expectEqual(Action.none, m.key(down(map.KEY_ESCAPE)));
    try std.testing.expectEqual(menu.Page.console, m.page);
    _ = m.key(down(map.KEY_ARROW_DOWN)); // Back: a pad has no Esc
    try std.testing.expectEqual(Action.save, m.key(down(map.KEY_ENTER)));
    try std.testing.expectEqual(menu.Page.shelf, m.page);
}
