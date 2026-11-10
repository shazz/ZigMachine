// mouse.zig's plane box (map_cart.zig VBOX_*, the firmware's cycles/bptrbox.h): the pointer stops
// where the cart draws. Matt, 9 Nov: GEM's arrow vanished in the borders, and once it was held to
// the visible window pt2-clone and klystrack (400x280 planes) lost their top and bottom rows.
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

/// The word bptrbox_pack writes, for raster pixels (ends exclusive).
fn word(x0: u32, y0: u32, x1: u32, y1: u32) u32 {
    return mc.VBOX_TAG | (x0 / mc.VBOX_X_UNIT) << mc.VBOX_X0_SHIFT | (x1 / mc.VBOX_X_UNIT) << mc.VBOX_X1_SHIFT |
        (y0 / mc.VBOX_Y_UNIT) << mc.VBOX_Y0_SHIFT | (y1 / mc.VBOX_Y_UNIT) << mc.VBOX_Y1_SHIFT;
}

const BX = map.PTR_BORDER_X;
const BY = map.PTR_BORDER_Y;
const GEM = word(BX, BY, map.PTR_WIDTH - BX, map.PTR_HEIGHT - BY); // one 640x200 plane
const PT2 = word(0, 0, map.PTR_WIDTH, map.PTR_HEIGHT); // a 400x280 FULLSCREEN plane

fn decode(w: u32) ?m.Box {
    var words = [_]u32{0} ** 1024; // a 4 KiB window top
    words[(words.len * 4 - mc.VBOX_FROM_TOP) / 4] = w;
    return m.planeBox(bus.Ddr{ .words = &words });
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

test "a plane over the borders (pt2-clone, klystrack) reaches the raster's top and bottom rows" {
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(PT2));
    var w = corner(&mo, -100_000, -100_000);
    try std.testing.expectEqual(@as(u32, 0), x(w));
    try std.testing.expectEqual(@as(u32, 0), y(w));
    w = corner(&mo, 100_000, 100_000);
    try std.testing.expectEqual(map.PTR_WIDTH - 1, x(w));
    try std.testing.expectEqual(map.PTR_HEIGHT - 1, y(w));
}

test "no box word, or one the firmware would not write, is the whole raster" {
    try std.testing.expectEqual(@as(?m.Box, null), decode(0)); // a load zeroed it: older firmware
    try std.testing.expectEqual(@as(?m.Box, null), decode(GEM & ~mc.VBOX_TAG_MASK)); // untagged
    try std.testing.expectEqual(@as(?m.Box, null), decode(mc.VMODE_TAG | (GEM & ~mc.VBOX_TAG_MASK)));
    try std.testing.expectEqual(@as(?m.Box, null), decode(word(400, 0, 400, 280))); // empty
    try std.testing.expectEqual(@as(?m.Box, null), decode(word(0, 0, 816, 280))); // off the raster
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(0));
    try std.testing.expectEqual(m.WHOLE, mo.planes);
    const w = corner(&mo, 100_000, 100_000);
    try std.testing.expectEqual(map.PTR_HEIGHT - 1, y(w));
}

test "a box that shrinks under the pointer pulls it in, at once" {
    var mo = m.Mouse{};
    mo.setPlaneBox(decode(PT2));
    _ = corner(&mo, -100_000, -100_000); // (0, 0), in the top-left border
    mo.setPlaneBox(decode(GEM)); // pt2 quit to GEM
    var w = one(&mo).?; // the clamped position is sent without a motion
    try std.testing.expectEqual(BX, x(w));
    try std.testing.expectEqual(BY, y(w));
    mo.setPlaneBox(decode(GEM));
    try std.testing.expectEqual(@as(?u32, null), one(&mo)); // no change, nothing sent
    mo.setPlaneBox(decode(PT2)); // a bigger box keeps the pointer where it is: nothing to send
    try std.testing.expectEqual(@as(?u32, null), one(&mo));
    w = corner(&mo, -1, 0); // and it may now go into the border
    try std.testing.expectEqual(BX - 1, x(w));
}

test "the box word sits between KOS's boot words and the boot sector's skip word" {
    try std.testing.expect(mc.VBOX_FROM_TOP >= mc.KOS_BOOT_FROM_TOP + 4);
    try std.testing.expect(mc.VBOX_FROM_TOP + 4 <= mc.BOOTSEC_SKIP_FROM_TOP);
    try std.testing.expect(map.PTR_WIDTH / mc.VBOX_X_UNIT <= mc.VBOX_FIELD_MASK);
    try std.testing.expect(map.PTR_HEIGHT / mc.VBOX_Y_UNIT <= mc.VBOX_FIELD_MASK);
    try std.testing.expectEqual(@as(u32, 0), BX % mc.VBOX_X_UNIT);
    try std.testing.expectEqual(@as(u32, 0), BY % mc.VBOX_Y_UNIT);
}
