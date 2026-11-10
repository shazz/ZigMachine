// mouse.zig against sealed-loader.js's pointer rules, and REG_POINTER's
// latch/SEQ rules in the simulated block (sim.zig mirrors zm_glass_regs.v).
const std = @import("std");
const map = @import("map.zig");
const sim = @import("sim.zig");
const memmap = @import("memmap");
const m = @import("mouse.zig");

fn x(w: u32) u32 {
    return (w >> map.PTR_X_SHIFT) & map.PTR_COORD_MASK;
}
fn y(w: u32) u32 {
    return (w >> map.PTR_Y_SHIFT) & map.PTR_COORD_MASK;
}
fn btn(w: u32) u32 {
    return (w >> map.PTR_BTN_SHIFT) & map.PTR_BTN_MASK;
}

fn one(mo: *m.Mouse) ?u32 {
    var out: [2]u32 = undefined;
    const n = mo.flush(&out);
    return if (n == 1) out[0] else null;
}

test "the coordinate space is the browser's canvas: the whole physical raster, borders included" {
    try std.testing.expectEqual(@as(u32, memmap.RASTER_WIDTH), map.PTR_WIDTH);
    try std.testing.expectEqual(@as(u32, memmap.RASTER_HEIGHT), map.PTR_HEIGHT);
    try std.testing.expectEqual(@as(u32, memmap.RASTER_BORDER_X), map.PTR_BORDER_X);
    try std.testing.expectEqual(@as(u32, memmap.RASTER_BORDER_Y), map.PTR_BORDER_Y);
    try std.testing.expectEqual(@as(u32, memmap.RASTER_VIS_WIDTH), map.PTR_WIDTH - 2 * map.PTR_BORDER_X);
    try std.testing.expectEqual(@as(u32, memmap.RASTER_VIS_HEIGHT), map.PTR_HEIGHT - 2 * map.PTR_BORDER_Y);
    try std.testing.expect(map.PTR_WIDTH - 1 <= map.PTR_COORD_MASK);
}

test "relative motion sums into an absolute position, y at half rate" {
    var mo = m.Mouse{};
    try std.testing.expectEqual(@as(u32, 400), mo.x()); // starts mid-screen: visible (320, 100)
    try std.testing.expectEqual(@as(u32, 140), mo.y());
    mo.update(m.EV_REL, m.REL_X, 10, 0);
    mo.update(m.EV_REL, m.REL_Y, -10, 0);
    const w = one(&mo).?;
    try std.testing.expectEqual(@as(u32, 410), x(w));
    try std.testing.expectEqual(@as(u32, 135), y(w));
    try std.testing.expectEqual(@as(u32, 0), btn(w));
    try std.testing.expectEqual(@as(?u32, null), one(&mo)); // nothing new since
}

test "with no box word the position clamps to the raster's edge, over the borders" {
    var mo = m.Mouse{};
    mo.update(m.EV_REL, m.REL_X, -100_000, 0);
    mo.update(m.EV_REL, m.REL_Y, std.math.maxInt(i32), 0); // saturates, never wraps
    var w = one(&mo).?;
    try std.testing.expectEqual(@as(u32, 0), x(w));
    try std.testing.expectEqual(map.PTR_HEIGHT - 1, y(w));
    mo.update(m.EV_REL, m.REL_X, 3, 0); // no debt piled up past the edge
    w = one(&mo).?;
    try std.testing.expectEqual(@as(u32, 3), x(w));
    mo.update(m.EV_REL, m.REL_X, 100_000, 0);
    try std.testing.expectEqual(map.PTR_WIDTH - 1, x(one(&mo).?));
    mo.update(m.EV_REL, m.REL_Y, -100_000, 0);
    try std.testing.expectEqual(@as(u32, 0), y(one(&mo).?));
}

test "the sensitivity scale keeps sub-pixel motion" {
    var mo = m.Mouse{ .scale = m.SCALE_ONE / 4 };
    mo.update(m.EV_REL, m.REL_X, 4, 0); // four counts: one pixel
    const x0 = x(one(&mo).?);
    try std.testing.expectEqual(@as(u32, 401), x0);
    for (0..3) |_| mo.update(m.EV_REL, m.REL_X, 1, 0);
    try std.testing.expectEqual(x0, mo.x());
    try std.testing.expectEqual(@as(?u32, null), one(&mo)); // a sub-pixel nudge writes nothing
    mo.update(m.EV_REL, m.REL_X, 1, 0);
    try std.testing.expectEqual(x0 + 1, x(one(&mo).?));
}

test "any button is bit 0, the wheel is dropped, a double-click pulses bit 1" {
    var mo = m.Mouse{};
    mo.update(m.EV_KEY, m.BTN_LEFT + 1, 1, 1000); // right button
    try std.testing.expectEqual(map.PTR_BTN_PRESS, btn(one(&mo).?));
    mo.update(m.EV_KEY, m.BTN_LEFT + 2, 1, 1001); // middle as well: still bit 0 only
    mo.update(m.EV_KEY, m.BTN_LEFT + 1, 0, 1002);
    try std.testing.expectEqual(@as(?u32, null), one(&mo)); // still held by the middle
    mo.update(m.EV_KEY, m.BTN_LEFT + 2, 0, 1003);
    try std.testing.expectEqual(@as(u32, 0), btn(one(&mo).?));
    mo.update(m.EV_REL, 0x08, 1, 0); // REL_WHEEL
    try std.testing.expectEqual(@as(?u32, null), one(&mo));
    mo.update(m.EV_KEY, m.BTN_LEFT, 1, 1300); // second press 300 ms after the first
    _ = one(&mo);
    mo.update(m.EV_KEY, m.BTN_LEFT, 0, 1350);
    var out: [2]u32 = undefined;
    try std.testing.expectEqual(@as(usize, 2), mo.flush(&out));
    try std.testing.expectEqual(map.PTR_BTN_DOUBLE, btn(out[0])); // the pulse, then the release
    try std.testing.expectEqual(@as(u32, 0), btn(out[1]));
    mo.update(m.EV_KEY, m.BTN_LEFT, 1, 1500); // a third press starts a new pair
    _ = one(&mo);
    mo.update(m.EV_KEY, m.BTN_LEFT, 0, 1550);
    try std.testing.expectEqual(@as(usize, 1), mo.flush(&out));
    mo.update(m.EV_KEY, m.BTN_LEFT, 1, 3000); // too slow
    _ = one(&mo);
    mo.update(m.EV_KEY, m.BTN_LEFT, 0, 3050);
    try std.testing.expectEqual(@as(usize, 1), mo.flush(&out));
}

test "mouse events are told apart from keys and pad buttons on a combo node" {
    try std.testing.expect(m.isMouse(m.EV_REL, m.REL_X));
    try std.testing.expect(m.isMouse(m.EV_KEY, m.BTN_LEFT));
    try std.testing.expect(!m.isMouse(m.EV_KEY, 30)); // KEY_A
    try std.testing.expect(!m.isMouse(m.EV_KEY, 0x120)); // BTN_TRIGGER: a joystick's
    try std.testing.expect(!m.isMouse(0x03, 0)); // EV_ABS: a stick
}

test "REG_POINTER: a click shorter than a poll is still seen, then released" {
    var g = sim.Glass{};
    const r = g.regs();
    r.write(map.REG_POINTER, 5 | map.PTR_BTN_PRESS << map.PTR_BTN_SHIFT);
    r.write(map.REG_POINTER, 6); // released before the firmware polled
    var p = g.pointer();
    try std.testing.expectEqual(@as(u32, 6), x(p));
    try std.testing.expectEqual(map.PTR_BTN_PRESS, btn(p)); // the press is latched
    const seq = p >> map.PTR_SEQ_SHIFT;
    try std.testing.expectEqual(@as(u32, 2), seq);
    g.pointerAck(seq - 1); // a stale ack changes nothing
    try std.testing.expectEqual(p, g.pointer());
    g.pointerAck(seq); // delivered: the release is now owed, so SEQ moves
    p = r.read(map.REG_POINTER);
    try std.testing.expectEqual(@as(u32, 0), btn(p));
    try std.testing.expectEqual(seq + 1, p >> map.PTR_SEQ_SHIFT);
    g.pointerAck(seq + 1); // nothing more owed
    try std.testing.expectEqual(p, g.pointer());
}

/// GEM's plane box (mouse_box_test.zig decodes it from the firmware's word): the visible window.
fn gemBox() m.Box {
    const s = m.SCALE_ONE;
    return .{
        .x0 = @as(i32, map.PTR_BORDER_X) * s,
        .y0 = @as(i32, map.PTR_BORDER_Y) * s,
        .x1 = @as(i32, map.PTR_WIDTH - map.PTR_BORDER_X) * s - 1,
        .y1 = @as(i32, map.PTR_HEIGHT - map.PTR_BORDER_Y) * s - 1,
    };
}

// The desk mode (HW 1.17.0, map_cart.zig VMODE_*): the picture is 640x480 at 1:1, so the word
// covers it at the border offset, y at full rate, and the firmware's border subtraction
// (glass_input.c) hands the cart 0..639 x 0..479.
test "the desk mode: y at full rate, the position held to the 640x480 picture" {
    try std.testing.expectEqual(@as(u32, memmap.DESK_WIDTH), map.PTR_DESK_WIDTH);
    try std.testing.expectEqual(@as(u32, memmap.DESK_HEIGHT), map.PTR_DESK_HEIGHT);
    try std.testing.expect(map.PTR_BORDER_Y + map.PTR_DESK_HEIGHT - 1 <= map.PTR_COORD_MASK);
    var mo = m.Mouse{};
    mo.setDesk(true);
    try std.testing.expectEqual(@as(u32, 400), x(one(&mo).?)); // a mode change sends the position
    mo.update(m.EV_REL, m.REL_Y, 10, 0);
    try std.testing.expectEqual(@as(u32, 150), y(one(&mo).?)); // 140 + 10: square pixels
    mo.update(m.EV_REL, m.REL_X, -100_000, 0);
    mo.update(m.EV_REL, m.REL_Y, 100_000, 0);
    const w = one(&mo).?;
    try std.testing.expectEqual(map.PTR_BORDER_X, x(w)); // the desk's x 0, not the black side bar
    try std.testing.expectEqual(map.PTR_BORDER_Y + map.PTR_DESK_HEIGHT - 1, y(w)); // its row 479
    mo.setPlaneBox(gemBox()); // the desk ignores the planes' box
    try std.testing.expectEqual(@as(?u32, null), one(&mo));
    mo.setDesk(false); // back to a plane mode: clamped into the planes' box
    try std.testing.expectEqual(map.PTR_HEIGHT - map.PTR_BORDER_Y - 1, y(one(&mo).?));
    mo.update(m.EV_REL, m.REL_Y, -10, 0);
    try std.testing.expectEqual(map.PTR_HEIGHT - map.PTR_BORDER_Y - 1 - 5, y(one(&mo).?)); // half rate again
    mo.setDesk(false);
    try std.testing.expectEqual(@as(?u32, null), one(&mo)); // no change, nothing sent
}

test "the firmware's mode word: tagged desk only, anything else the plane modes" {
    const mc = @import("map_cart.zig");
    const bus = @import("bus.zig");
    var words = [_]u32{0} ** 1024; // a 4 KiB window top
    const ddr = bus.Ddr{ .words = &words };
    const at = (words.len * 4 - mc.VMODE_FROM_TOP) / 4;
    try std.testing.expect(!m.deskMode(ddr)); // zeroed by a load: an older firmware, no frame yet
    words[at] = mc.VMODE_TAG | mc.VMODE_DESK;
    try std.testing.expect(m.deskMode(ddr));
    words[at] = mc.VMODE_TAG;
    try std.testing.expect(!m.deskMode(ddr));
    words[at] = mc.VMODE_DESK; // untagged: not a word the firmware wrote
    try std.testing.expect(!m.deskMode(ddr));
    try std.testing.expect(mc.VMODE_FROM_TOP > mc.KOS_FILE_FROM_TOP and mc.VMODE_FROM_TOP < mc.KOS_CGEN_FROM_TOP);
}
