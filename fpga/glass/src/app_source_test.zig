// F on the shelf: the floppy as the carts' source (app_source.zig). The mount itself needs
// the board (root, a real block device); these test what decides it: which device is a
// floppy, and what the menu shows and does.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const shelf = @import("shelf.zig");
const menu = @import("menu.zig");
const page_shelf = @import("page_shelf.zig");
const source = @import("app_source.zig");
const View = @import("page_debug.zig").View;
const BView = @import("page_budget.zig").View;

const io = std.testing.io;

/// A fake /sys/block device: `size` in 512-byte sectors, removable or not.
fn dev(root: std.Io.Dir, name: []const u8, size: []const u8, removable: []const u8) !void {
    var p: [64]u8 = undefined;
    try root.createDirPath(io, try std.fmt.bufPrint(&p, "sys/block/{s}", .{name}));
    try root.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&p, "sys/block/{s}/size", .{name}), .data = size });
    try root.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&p, "sys/block/{s}/removable", .{name}), .data = removable });
}

test "the floppy is the removable sd disk of floppy size, not a stick, a fixed disk or an empty drive" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var rp: [96]u8 = undefined;
    const root = try std.fmt.bufPrint(&rp, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), source.find(io, root, &buf)); // no /sys/block at all
    try dev(tmp.dir, "mmcblk0", "61497344\n", "0\n"); // the SD card: not sd*
    try dev(tmp.dir, "sdb", "30031872\n", "1\n"); // a USB stick: far too big
    try dev(tmp.dir, "sdc", "2880\n", "0\n"); // floppy-sized but fixed
    try dev(tmp.dir, "sdd", "0\n", "1\n"); // a floppy drive with no disk in it
    try std.testing.expectEqual(@as(?[]const u8, null), source.find(io, root, &buf));
    try dev(tmp.dir, "sda", "2880\n", "1\n"); // the USB floppy with a 1.44 MB disk
    try std.testing.expectEqualStrings("sda", source.find(io, root, &buf).?);
}

fn row(o: *const osd.Osd, r: u32) []const u8 {
    const S = struct {
        var buf: [osd.COLS]u8 = undefined;
    };
    for (&S.buf, 0..) |*c, i| c.* = @truncate(o.text[r * osd.COLS + i]);
    return std.mem.trimEnd(u8, &S.buf, " ");
}

/// A content row (right of the section strip and its gap), trailing blanks dropped.
fn body(o: *const osd.Osd, r: u32) []const u8 {
    const full = row(o, r);
    return full[@min(osd.BODY_COL, full.len)..];
}

test "F on the shelf asks for the source switch; the title and the empty shelf say FLOPPY" {
    var d = [_]shelf.Disk{.{ .file = "a.zmd", .title = "TUTORIAL" }};
    var m = menu.Menu{ .disks = &d };
    try std.testing.expectEqual(menu.Action.source, m.key('f' | map.KEY_DOWN));
    try std.testing.expectEqual(menu.Action.source, m.key('F' | map.KEY_DOWN));
    var o = osd.Osd{};
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings(" ZIGMACHINE  SHELF     1/1   >", row(&o, 0));
    m.floppy = true;
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings(" ZIGMACHINE  FLOPPY    1/1   >", row(&o, 0));
    m.disks = &.{};
    m.draw(&o, &View{}, &BView{});
    try std.testing.expectEqualStrings("no .zmd disk on the floppy", body(&o, page_shelf.FIRST));
    try std.testing.expectEqualStrings("FLOPPY", &[_]u8{ row(&o, 2)[0], row(&o, 3)[0], row(&o, 4)[0], row(&o, 5)[0], row(&o, 6)[0], row(&o, 7)[0] }); // the strip
    try std.testing.expect(menu.HINT.len <= osd.COLS);
}
