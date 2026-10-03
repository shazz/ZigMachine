// USB mouse -> REG_POINTER: what the browser hands demo.pointer(x, y, buttons)
// (docs/sealed-loader.js, "Pointer input"). A mouse reports relative motion,
// the browser an absolute position on the canvas, so the motion is summed into
// a position in the cart's coordinate space (map.PTR_WIDTH x PTR_HEIGHT) and
// clamped to it, as a pointer stops at the edge of a screen.
//
// The browser's buttons are not the mouse's: ANY button is bit 0, and a
// double-click is a one-off pulse of bit 1. Linux has no double-click, so it
// is timed here from the events' own timestamps (deterministic in tests).
const std = @import("std");
const map = @import("map.zig");

// linux/input-event-codes.h
pub const EV_SYN = 0x00;
pub const EV_KEY = 0x01;
pub const EV_REL = 0x02;
pub const SYN_REPORT = 0;
pub const REL_X = 0x00;
pub const REL_Y = 0x01;
pub const BTN_LEFT = 0x110; // BTN_RIGHT 0x111, BTN_MIDDLE 0x112, ... BTN_TASK 0x117
pub const BTN_MOUSE_LAST = 0x117;

/// The OS default (GTK, Windows' 500 is the slow end): a second press within it is a double-click.
pub const DOUBLE_MS = 400;
/// Sensitivity in 1/256 pixel per mouse count: 256 = one pixel a count.
pub const SCALE_ONE = 256;

/// The events a mouse sends; a combo keyboard+mouse node sends both kinds, so
/// routing is per event, not per device. Joypad buttons start at 0x120.
pub fn isMouse(ev_type: u16, code: u16) bool {
    return ev_type == EV_REL or (ev_type == EV_KEY and code >= BTN_LEFT and code <= BTN_MOUSE_LAST);
}

const MAX_X: i32 = @as(i32, map.PTR_WIDTH) * SCALE_ONE - 1;
const MAX_Y: i32 = @as(i32, map.PTR_HEIGHT) * SCALE_ONE - 1;

pub const Mouse = struct {
    // Sub-pixel position, so a scale below one pixel a count still moves.
    fx: i32 = map.PTR_WIDTH / 2 * SCALE_ONE, // the middle, on a pixel's edge
    fy: i32 = map.PTR_HEIGHT / 2 * SCALE_ONE,
    scale: i32 = SCALE_ONE,
    held: u32 = 0, // physical buttons down, bit (code - BTN_LEFT)
    last_press_ms: ?i64 = null,
    double: bool = false, // the release that ends a double-click owes the pulse
    dirty: bool = false,
    sent: ?u32 = null, // the last word written, to skip a sub-pixel nudge

    pub fn x(self: Mouse) u32 {
        return @intCast(@divFloor(self.fx, SCALE_ONE));
    }

    pub fn y(self: Mouse) u32 {
        return @intCast(@divFloor(self.fy, SCALE_ONE));
    }

    pub fn word(self: Mouse, buttons: u32) u32 {
        return self.x() << map.PTR_X_SHIFT | self.y() << map.PTR_Y_SHIFT | buttons << map.PTR_BTN_SHIFT;
    }

    /// Fold one mouse event in; the words to write come out at the next SYN_REPORT (`flush`).
    pub fn update(self: *Mouse, ev_type: u16, code: u16, value: i32, ms: i64) void {
        switch (ev_type) {
            // A ZigMachine row is twice as tall as its column is wide (640x200 on
            // a 4:3 screen), so y moves half as many rows a count as x moves columns.
            EV_REL => switch (code) {
                REL_X => self.fx = std.math.clamp(self.fx +| value *| self.scale, 0, MAX_X),
                REL_Y => self.fy = std.math.clamp(self.fy +| @divTrunc(value *| self.scale, 2), 0, MAX_Y),
                else => return, // the browser has no wheel: REL_WHEEL is dropped
            },
            EV_KEY => self.button(code - BTN_LEFT, value, ms),
            else => return,
        }
        self.dirty = true;
    }

    fn button(self: *Mouse, bit: u16, value: i32, ms: i64) void {
        if (value == 2) return; // a mouse has no auto-repeat, but a remapped key might
        const was = self.held;
        if (value != 0) self.held |= @as(u32, 1) << @intCast(bit) else self.held &= ~(@as(u32, 1) << @intCast(bit));
        if (was == 0 and self.held != 0) { // a press: the second within DOUBLE_MS is a double-click
            const quick = if (self.last_press_ms) |t| ms - t <= DOUBLE_MS else false;
            self.double = quick;
            self.last_press_ms = if (quick) null else ms; // a third press starts a new pair
        }
    }

    /// The REG_POINTER words this report owes: the state, and after the release
    /// that ends a double-click the browser's bit-1 pulse before the release.
    pub fn flush(self: *Mouse, out: *[2]u32) usize {
        if (!self.dirty) return 0;
        self.dirty = false;
        const btn: u32 = if (self.held != 0) map.PTR_BTN_PRESS else 0;
        var n: usize = 0;
        if (self.double and self.held == 0) {
            self.double = false;
            out[n] = self.word(map.PTR_BTN_DOUBLE);
            n += 1;
        }
        const w = self.word(btn);
        if (n == 0 and self.sent == w) return 0;
        out[n] = w;
        self.sent = w;
        return n + 1;
    }

    /// Let go of every button (the OSD opened): the word that tells the cart, or null.
    pub fn release(self: *Mouse) ?u32 {
        self.double = false;
        self.dirty = false;
        if (self.held == 0) return null;
        self.held = 0;
        self.sent = self.word(0);
        return self.sent;
    }
};
