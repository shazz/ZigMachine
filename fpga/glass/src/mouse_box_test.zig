// mouse.zig's plane box (map_cart.zig VBOX_*, the firmware's cycles/bptrbox.h): the pointer stops
// where the cart's picture is. Matt, 9 Nov: GEM's arrow vanished in the borders, and once it was held to
// the visible window pt2-clone and klystrack (400x280 planes) lost their top and bottom rows; held
// to their whole plane, it vanished past their pictures (their cursor is drawn only over them).
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const m = @import("mouse.zig");

fn x(w: u32) u32 {
    return (w >> map.PTR_X_SHIFT) & map.PTR_COORD_MASK;
}
fn y(w: u32) u32 {
    return (w >> map.PTR_Y_SHIFT) & map.PTR_COORD_MASK;
}
fn one(mo: *m.Mouse) ?u32 {
    var out: [2]u32 = undefined;
    const n = mo.flush(&out);
    return if (n == 1) out[0] else null;
}

/// The words bptrbox_pack writes, for raster pixels (ends exclusive).
const Words = struct { x: u32, y: u32 };
fn words(x0: u32, y0: u32, x1: u32, y1: u32) Words {
    return .{ .x = mc.VBOX_X_TAG | x0 | x1 << mc.VBOX_HI_SHIFT, .y = mc.VBOX_Y_TAG | y0 | y1 << mc.VBOX_HI_SHIFT };
}

const BX = map.PTR_BORDER_X;
const BY = map.PTR_BORDER_Y;
const GEM = words(BX, BY, map.PTR_WIDTH - BX, map.PTR_HEIGHT - BY); // one 640x200 plane
const PT2 = words(BX, 12, map.PTR_WIDTH - BX, 12 + 255); // 320x255 at (40, 12) of a 400x280 plane
const WIDE = words(0, 0, map.PTR_WIDTH, map.PTR_HEIGHT); // a picture over the whole raster

fn decode(w: Words) ?m.Box {
    var win = [_]u32{0} ** 1024; // a 4 KiB window top
    win[(win.len * 4 - mc.VBOX_X_FROM_TOP) / 4] = w.x;
    win[(win.len * 4 - mc.VBOX_Y_FROM_TOP) / 4] = w.y;
    return m.planeBox(bus.Ddr{ .words = &win });
}

fn corner(mo: *m.Mouse, dx: i32, dy: i32) u32 {
    mo.update(m.EV_REL, m.REL_X, dx, 0);
    mo.update(m.EV_REL, m.REL_Y, dy, 0);
    return one(mo).?;
}

test "GEM's box is the visible window: the arrow never goes into the borders" {
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(GEM));
    var w = corner(&mo, -100_000, -100_000);
    try std.testing.expectEqual(BX, x(w));
    try std.testing.expectEqual(BY, y(w));
    w = corner(&mo, 100_000, 100_000);
    try std.testing.expectEqual(map.PTR_WIDTH - BX - 1, x(w)); // 719
    try std.testing.expectEqual(map.PTR_HEIGHT - BY - 1, y(w)); // 239
}

test "pt2-clone's picture: its top and bottom rows are reachable, the rows past them are not" {
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(PT2));
    var w = corner(&mo, -100_000, -100_000);
    try std.testing.expectEqual(BX, x(w));
    try std.testing.expectEqual(@as(u32, 12), y(w)); // its row 0, in the top border; row 11 is not
    w = corner(&mo, 100_000, 100_000);
    try std.testing.expectEqual(map.PTR_WIDTH - BX - 1, x(w));
    try std.testing.expectEqual(@as(u32, 266), y(w)); // its row 254; 267 is past the picture
}

test "a picture over the whole raster reaches every corner" {
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(WIDE));
    var w = corner(&mo, -100_000, -100_000);
    try std.testing.expectEqual(@as(u32, 0), x(w));
    try std.testing.expectEqual(@as(u32, 0), y(w));
    w = corner(&mo, 100_000, 100_000);
    try std.testing.expectEqual(map.PTR_WIDTH - 1, x(w));
    try std.testing.expectEqual(map.PTR_HEIGHT - 1, y(w));
}

test "no box words, or ones the firmware would not write, are the whole raster" {
    const none = Words{ .x = 0, .y = 0 };
    try std.testing.expectEqual(@as(?m.Box, null), decode(none)); // a load zeroed them: older firmware
    try std.testing.expectEqual(@as(?m.Box, null), decode(.{ .x = GEM.x, .y = 0 })); // half a box
    try std.testing.expectEqual(@as(?m.Box, null), decode(.{ .x = GEM.y, .y = GEM.x })); // tags swapped
    try std.testing.expectEqual(@as(?m.Box, null), decode(.{ .x = 0x4200_0000 | GEM.x & 0xFFFFFF, .y = GEM.y })); // the old "B" word
    try std.testing.expectEqual(@as(?m.Box, null), decode(words(400, 0, 400, 280))); // empty
    try std.testing.expectEqual(@as(?m.Box, null), decode(words(0, 0, 801, 280))); // off the raster
    try std.testing.expectEqual(@as(?m.Box, null), decode(words(0, 0, 800, 281)));
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(none));
    try std.testing.expectEqual(m.WHOLE, mo.planes);
    const w = corner(&mo, 100_000, 100_000);
    try std.testing.expectEqual(map.PTR_HEIGHT - 1, y(w));
}

test "a box that shrinks under the pointer pulls it in, at once" {
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(WIDE));
    _ = corner(&mo, -100_000, -100_000); // (0, 0), in the top-left border
    mo.setPlaneBox(decode(GEM)); // the program quit to GEM
    var w = one(&mo).?; // the clamped position is sent without a motion
    try std.testing.expectEqual(BX, x(w));
    try std.testing.expectEqual(BY, y(w));
    mo.setPlaneBox(decode(GEM));
    try std.testing.expectEqual(@as(?u32, null), one(&mo)); // no change, nothing sent
    mo.setPlaneBox(decode(WIDE)); // a bigger box keeps the pointer where it is: nothing to send
    try std.testing.expectEqual(@as(?u32, null), one(&mo));
    w = corner(&mo, -1, 0); // and it may now go into the border
    try std.testing.expectEqual(BX - 1, x(w));
}

test "the box words sit in free words of the window's top" {
    try std.testing.expect(mc.VBOX_Y_FROM_TOP >= mc.KOS_BOOT_FROM_TOP + 4);
    try std.testing.expect(mc.VBOX_Y_FROM_TOP + 4 <= mc.BOOTSEC_SKIP_FROM_TOP);
    try std.testing.expect(mc.VBOX_X_FROM_TOP >= mc.KOS_FILE_FROM_TOP + 4);
    try std.testing.expect(mc.VBOX_X_FROM_TOP + 4 <= mc.VMODE_FROM_TOP);
    try std.testing.expect(map.PTR_WIDTH <= mc.VBOX_FIELD_MASK and map.PTR_HEIGHT <= mc.VBOX_FIELD_MASK);
    try std.testing.expect(mc.VBOX_FIELD_MASK << mc.VBOX_HI_SHIFT & mc.VBOX_TAG_MASK == 0);
}
