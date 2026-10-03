// pad.zig: each kind of pad Linux reports, held bits in, demo.input() bits out.
// tests/test_glass_input.py breaks each rule here and requires a failure.
const std = @import("std");
const map = @import("map.zig");
const p = @import("pad.zig");

test "an analog stick: a third of its declared range from centre counts, either way" {
    // An XInput stick declares -32768..32767; the threshold is (max-min)/6 = 10922 off centre.
    var pad = p.Pad{ .x = .{ .min = -32768, .max = 32767 }, .y = .{ .min = -32768, .max = 32767 } };
    try std.testing.expect(!pad.update(p.EV_ABS, p.ABS_X, 10_922)); // at the threshold: resting
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_X, 10_923));
    try std.testing.expectEqual(map.JOY_RIGHT, pad.bits);
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_X, -10_923));
    try std.testing.expectEqual(map.JOY_LEFT, pad.bits);
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_X, 0)); // back to centre lets go
    try std.testing.expectEqual(@as(u32, 0), pad.bits);
    try std.testing.expect(!pad.update(p.EV_ABS, p.ABS_Y, -10_922));
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_Y, -32768)); // y grows downwards
    try std.testing.expectEqual(map.JOY_UP, pad.bits);
}

test "an unsigned stick (0..255) centres on its own midpoint, not on zero" {
    var pad = p.Pad{ .x = .{ .min = 0, .max = 255 }, .y = .{ .min = 0, .max = 255 } };
    try std.testing.expect(!pad.update(p.EV_ABS, p.ABS_X, 0 + 127 - 42)); // inside: 127 +- 42
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_X, 127 - 43));
    try std.testing.expectEqual(map.JOY_LEFT, pad.bits);
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_Y, 255));
    try std.testing.expectEqual(map.JOY_LEFT | map.JOY_DOWN, pad.bits);
}

test "a hat d-pad: -1, 0, 1 on each axis, any step counts" {
    var pad = p.Pad{ .x = .{ .min = 0, .max = 255 } }; // the stick's range never applies to the hat
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_HAT0Y, -1));
    try std.testing.expectEqual(map.JOY_UP, pad.bits);
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_HAT0Y, 1));
    try std.testing.expectEqual(map.JOY_DOWN, pad.bits);
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_HAT0X, 1)); // a diagonal
    try std.testing.expectEqual(map.JOY_DOWN | map.JOY_RIGHT, pad.bits);
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_HAT0Y, 0));
    try std.testing.expect(pad.update(p.EV_ABS, p.ABS_HAT0X, -1));
    try std.testing.expectEqual(map.JOY_LEFT, pad.bits);
}

test "a d-pad as buttons (BTN_DPAD_*): press and release each direction" {
    var pad = p.Pad{};
    const dirs = [_]u32{ map.JOY_UP, map.JOY_DOWN, map.JOY_LEFT, map.JOY_RIGHT };
    for (dirs, 0..) |bit, i| {
        const code: u16 = p.BTN_DPAD_UP + @as(u16, @intCast(i));
        try std.testing.expect(pad.update(p.EV_KEY, code, 1));
        try std.testing.expectEqual(bit, pad.bits);
        try std.testing.expect(pad.update(p.EV_KEY, code, 0));
        try std.testing.expectEqual(@as(u32, 0), pad.bits);
    }
}

test "fire: a joystick's trigger and a gamepad's south and east buttons" {
    for ([_]u16{ p.BTN_TRIGGER, p.BTN_SOUTH, p.BTN_EAST }) |code| {
        var pad = p.Pad{};
        try std.testing.expect(pad.update(p.EV_KEY, code, 1));
        try std.testing.expectEqual(map.JOY_FIRE, pad.bits);
        try std.testing.expect(!pad.update(p.EV_KEY, code, 2)); // a repeat changes nothing
        try std.testing.expect(pad.update(p.EV_KEY, code, 0));
        try std.testing.expectEqual(@as(u32, 0), pad.bits);
    }
    var pad = p.Pad{};
    try std.testing.expect(!pad.update(p.EV_KEY, 0x133, 1)); // BTN_NORTH is not fire
}
