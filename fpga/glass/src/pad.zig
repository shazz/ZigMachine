// USB joypad -> REG_JOY: the held directions and fire, as the demo.input()
// codes (up 0, down 1, left 2, right 3, fire 5). The cart CPU's firmware turns
// the bits' edges into input()/inputRelease() calls, as the browser turns arrow
// keys into them. A d-pad reports a hat or buttons; a stick reports an axis
// with a range the device declares, read once with EVIOCGABS (evdev.zig).
const std = @import("std");
const map = @import("map.zig");

// linux/input-event-codes.h
pub const EV_KEY = 0x01;
pub const EV_ABS = 0x03;
pub const ABS_X = 0x00;
pub const ABS_Y = 0x01;
pub const ABS_HAT0X = 0x10;
pub const ABS_HAT0Y = 0x11;
pub const BTN_TRIGGER = 0x120; // a classic joystick's fire
pub const BTN_SOUTH = 0x130; // a gamepad's A / cross
pub const BTN_EAST = 0x131;
pub const BTN_DPAD_UP = 0x220; // up, down, left, right = 0x220..0x223

pub const Range = struct { min: i32 = -1, max: i32 = 1 };

pub const Pad = struct {
    bits: u32 = 0,
    x: Range = .{},
    y: Range = .{},

    fn set(self: *Pad, bit: u32, on: bool) void {
        if (on) self.bits |= bit else self.bits &= ~bit;
    }

    // Past a third of the way from centre counts as pushed: a worn stick rests off-centre.
    fn axis(self: *Pad, v: i32, r: Range, neg: u32, pos: u32) void {
        const mid = @divTrunc(r.min + r.max, 2);
        const dead = @divTrunc(r.max - r.min, 6); // 0 for a hat: any step counts
        self.set(neg, v < mid - dead);
        self.set(pos, v > mid + dead);
    }

    /// Fold one evdev event in; true when the held bits changed.
    pub fn update(self: *Pad, ev_type: u16, code: u16, value: i32) bool {
        const before = self.bits;
        switch (ev_type) {
            EV_ABS => switch (code) {
                ABS_X => self.axis(value, self.x, map.JOY_LEFT, map.JOY_RIGHT),
                ABS_Y => self.axis(value, self.y, map.JOY_UP, map.JOY_DOWN),
                ABS_HAT0X => self.axis(value, .{}, map.JOY_LEFT, map.JOY_RIGHT),
                ABS_HAT0Y => self.axis(value, .{}, map.JOY_UP, map.JOY_DOWN),
                else => {},
            },
            EV_KEY => switch (code) {
                BTN_TRIGGER, BTN_SOUTH, BTN_EAST => self.set(map.JOY_FIRE, value != 0),
                BTN_DPAD_UP => self.set(map.JOY_UP, value != 0),
                BTN_DPAD_UP + 1 => self.set(map.JOY_DOWN, value != 0),
                BTN_DPAD_UP + 2 => self.set(map.JOY_LEFT, value != 0),
                BTN_DPAD_UP + 3 => self.set(map.JOY_RIGHT, value != 0),
                else => {},
            },
            else => {},
        }
        return self.bits != before;
    }
};

test "a hat, buttons and a stick with its own range" {
    var p = Pad{ .x = .{ .min = 0, .max = 255 }, .y = .{ .min = 0, .max = 255 } };
    try std.testing.expect(p.update(EV_ABS, ABS_HAT0X, -1));
    try std.testing.expectEqual(map.JOY_LEFT, p.bits);
    try std.testing.expect(p.update(EV_ABS, ABS_HAT0X, 0));
    try std.testing.expect(p.update(EV_KEY, BTN_SOUTH, 1));
    try std.testing.expectEqual(map.JOY_FIRE, p.bits);
    try std.testing.expect(!p.update(EV_ABS, ABS_X, 140)); // inside the dead zone
    try std.testing.expect(p.update(EV_ABS, ABS_X, 250));
    try std.testing.expectEqual(map.JOY_FIRE | map.JOY_RIGHT, p.bits);
    try std.testing.expect(p.update(EV_ABS, ABS_Y, 0));
    try std.testing.expectEqual(map.JOY_FIRE | map.JOY_RIGHT | map.JOY_UP, p.bits);
    try std.testing.expect(!p.update(EV_KEY, 0x2FF, 1)); // a button it does not know
}
