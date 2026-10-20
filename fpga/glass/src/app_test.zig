// The glass program driven like a user would, against the simulated block:
// F12, the menu, keys reaching the cart, a load, and a cart that traps.
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const keymap = @import("keymap.zig");
const pad = @import("pad.zig");
const mouse = @import("mouse.zig");

const test_rig = @import("test_rig.zig");
const Rig = test_rig.Rig;
const press = test_rig.press;

test "the menu comes up, loads a disk, and the OSD gets out of the way" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expectEqual(@as(u32, map.OSD_INVERSE | ' '), r.glass.text[0]); // the title bar is on screen
    press(&a, keymap.KEY_ENTER); // the cursor starts on a.zmd
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
    try std.testing.expectEqual(@as(?usize, null), try r.loaded());
    try std.testing.expectEqual(@as(?usize, 0), a.current);
}

test "keys reach the cart only while the OSD is closed, and are released when it opens" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    _ = r.glass.pop(); // nothing queued by the load: the FIFO was flushed
    a.key(30, 1); // 'a' down, held
    try std.testing.expectEqual(@as(?u32, 'a' | map.KEY_DOWN), r.glass.pop());
    a.key(keymap.OSD_HOTKEY, 1);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expectEqual(@as(?u32, 'a'), r.glass.pop()); // released for the cart
    a.key(31, 1); // 's' goes to the menu, not the cart
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop());
    a.key(keymap.KEY_ESC, 1); // Esc closes the menu over a running cart
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
    a.padEvent(pad.EV_ABS, pad.ABS_HAT0X, 1, .{}, .{}, "pad");
    try std.testing.expectEqual(map.JOY_RIGHT, r.glass.joy);
    a.key(keymap.KEY_PAGEDOWN, 1); // the OSD's own key: a cart never sees it
    a.key(keymap.KEY_PAGEDOWN, 0);
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop());
}

test "a disk without a board image says so and nothing runs" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_DOWN);
    press(&a, keymap.KEY_ENTER);
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "NoBoardImage") != null);
    a.key(keymap.KEY_ESC, 1); // with no cart to go back to, the menu stays
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
}

test "a cart that traps brings the menu back and is held" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    r.glass.cart = .traps;
    a.tick();
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "trapped (code 5)") != null);
}

test "the mouse reaches the cart only while the OSD is closed; a held button is released first" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    a.mouseEvent(mouse.EV_REL, mouse.REL_X, 50, 0); // over the menu: dropped
    a.sync();
    try std.testing.expectEqual(@as(u32, 0), r.glass.ptr_seq);
    press(&a, keymap.KEY_ENTER); // load: the OSD closes
    a.mouseEvent(mouse.EV_REL, mouse.REL_X, 10, 0);
    a.mouseEvent(mouse.EV_KEY, mouse.BTN_LEFT, 1, 0);
    a.sync();
    const held = a.mouse.word(map.PTR_BTN_PRESS);
    try std.testing.expectEqual(held, r.glass.ptr);
    try std.testing.expectEqual(@as(u32, 330), a.mouse.x());
    a.key(keymap.OSD_HOTKEY, 1);
    try std.testing.expectEqual(a.mouse.word(0), r.glass.ptr); // released, kept in place
    const seq = r.glass.ptr_seq;
    a.mouseEvent(mouse.EV_KEY, mouse.BTN_LEFT, 0, 5); // the real release, behind the menu
    a.mouseEvent(mouse.EV_REL, mouse.REL_Y, 40, 5);
    a.sync();
    try std.testing.expectEqual(seq, r.glass.ptr_seq); // nothing reached the cart
}
