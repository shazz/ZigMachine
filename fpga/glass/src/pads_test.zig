// pads.zig + app_pad.zig: two joysticks, one per player (R83). tests/test_glass_input.py breaks
// each rule and requires a failure.
const std = @import("std");
const map = @import("map.zig");
const keymap = @import("keymap.zig");
const pad = @import("pad.zig");
const pads = @import("pads.zig");
const test_rig = @import("test_rig.zig");
const Rig = test_rig.Rig;
const press = test_rig.press;

const R: pad.Range = .{};

fn running(r: *Rig) !@import("app.zig").App {
    var a = try r.app();
    press(&a, keymap.KEY_ENTER); // the cursor starts on a.zmd: the cart runs, the OSD is closed
    _ = r.glass.pop();
    return a;
}

test "the first pad heard is player 1 (REG_JOY), the second player 2 (a key FIFO state word)" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    a.padEvent(4, pad.EV_ABS, pad.ABS_HAT0X, -1, R, R, "iCode"); // event4 speaks first
    try std.testing.expectEqual(map.JOY_LEFT, r.glass.joy);
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop()); // player 2 not touched
    a.padEvent(3, pad.EV_ABS, pad.ABS_HAT0X, 1, R, R, "iCode");
    a.padEvent(3, pad.EV_KEY, pad.BTN_TRIGGER, 1, R, R, "iCode");
    try std.testing.expectEqual(map.JOY_LEFT, r.glass.joy); // player 1 unchanged by pad 2
    try std.testing.expectEqual(@as(?u32, map.KEY_P2_STATE | map.JOY_RIGHT), r.glass.pop());
    try std.testing.expectEqual(@as(?u32, map.KEY_P2_STATE | map.JOY_RIGHT | map.JOY_FIRE), r.glass.pop());
    a.padEvent(3, pad.EV_ABS, pad.ABS_HAT0X, 0, R, R, "iCode");
    a.padEvent(3, pad.EV_KEY, pad.BTN_TRIGGER, 0, R, R, "iCode");
    try std.testing.expectEqual(@as(?u32, map.KEY_P2_STATE | map.JOY_FIRE), r.glass.pop());
    try std.testing.expectEqual(@as(?u32, map.KEY_P2_STATE), r.glass.pop());
}

test "one pad changes nothing: REG_JOY only, no key word" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    a.padEvent(3, pad.EV_KEY, pad.BTN_SOUTH, 1, R, R, "pad");
    a.padEvent(3, pad.EV_ABS, pad.ABS_HAT0Y, 1, R, R, "pad");
    try std.testing.expectEqual(map.JOY_FIRE | map.JOY_DOWN, r.glass.joy);
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop());
}

test "the OSD takes either pad, the cart gets none, and opening lets go of both players" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    a.padEvent(3, pad.EV_ABS, pad.ABS_HAT0X, 1, R, R, "p1");
    a.padEvent(4, pad.EV_ABS, pad.ABS_HAT0X, 1, R, R, "p2");
    try std.testing.expectEqual(@as(?u32, map.KEY_P2_STATE | map.JOY_RIGHT), r.glass.pop());
    a.key(keymap.OSD_HOTKEY, 1);
    try std.testing.expectEqual(@as(u32, 0), r.glass.joy);
    try std.testing.expectEqual(@as(?u32, map.KEY_P2_STATE), r.glass.pop()); // player 2 released
    const at = a.menu.list.cursor;
    a.padEvent(4, pad.EV_ABS, pad.ABS_HAT0Y, 1, R, R, "p2"); // pad 2 moves the menu
    try std.testing.expectEqual(at + 1, a.menu.list.cursor);
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop()); // and the cart hears nothing
    try std.testing.expectEqual(@as(u32, 0), r.glass.joy);
}

test "slots: plug order, a third pad is the OSD's only, an idle pad's slot is reused, all held: ignored" {
    var p = pads.Pads{};
    try std.testing.expectEqual(@as(?usize, 0), p.slot(7));
    try std.testing.expectEqual(@as(?usize, 1), p.slot(2));
    try std.testing.expectEqual(@as(?usize, 0), p.slot(7)); // keyed by node, not by order of events
    p.slots[0].pad.bits = map.JOY_UP;
    _ = p.slot(9);
    _ = p.slot(11);
    try std.testing.expectEqual(@as(u32, map.JOY_UP), p.player(0));
    try std.testing.expectEqual(@as(u32, 0), p.player(1));
    p.slots[0].pad.bits = map.JOY_FIRE;
    p.slots[1].pad.bits = map.JOY_FIRE;
    p.slots[2].pad.bits = map.JOY_FIRE;
    p.slots[3].pad.bits = map.JOY_FIRE;
    try std.testing.expectEqual(@as(?usize, null), p.slot(12)); // all four held
    p.slots[2].pad.bits = 0; // node 9 idles: its slot goes to 12, the order of the others kept
    try std.testing.expectEqual(@as(?usize, 3), p.slot(12));
    try std.testing.expectEqual(@as(u16, 2), p.slots[1].num);
    try std.testing.expectEqual(@as(u16, 11), p.slots[2].num);
}

test "an event with no meaning is reported once per code, and only so many in all" {
    var p = pads.Pads{};
    try std.testing.expect(!p.firstUnknown(pad.EV_KEY, pad.BTN_SOUTH)); // known
    try std.testing.expect(!p.firstUnknown(0x00, 0)); // EV_SYN
    try std.testing.expect(p.firstUnknown(pad.EV_KEY, 0x2FF));
    try std.testing.expect(!p.firstUnknown(pad.EV_KEY, 0x2FF));
    try std.testing.expect(p.firstUnknown(pad.EV_ABS, 0x05)); // ABS_RZ
    var n: u16 = 0;
    while (n < 40) : (n += 1) _ = p.firstUnknown(pad.EV_KEY, 0x300 + n);
    try std.testing.expect(!p.firstUnknown(pad.EV_KEY, 0x300 + 41)); // the log is full: silent
}

test "player 2's word carries the JOY bits and nothing else" {
    try std.testing.expectEqual(map.KEY_P2_STATE | 0x2F, pads.p2Word(0xFFFF_FFFF & ~@as(u32, 0x10)));
}
