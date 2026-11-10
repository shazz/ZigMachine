// USB mouse -> REG_POINTER: what the browser hands demo.pointer(x, y, buttons)
// (docs/sealed-loader.js, "Pointer input"). A mouse reports relative motion,
// the browser an absolute position on the canvas, so the motion is summed into
// a position on the whole physical raster (map.PTR_WIDTH x PTR_HEIGHT, borders
// included, as the browser's canvas) and clamped to where the cart draws (the
// firmware's box words, planeBox), as a pointer stops at the edge of a screen.
// The firmware makes it the browser's coordinates.
//
// The browser's buttons are not the mouse's: ANY button is bit 0, and a
// double-click is a one-off pulse of bit 1. Linux has no double-click, so it
// is timed here from the events' own timestamps (deterministic in tests).
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");

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
/// The firmware's video mode word in the cart window (map_cart.zig VMODE_*): is the cart in the
/// desk mode? An untagged word (an older firmware, no frame yet) is the plane modes.
pub fn deskMode(ddr: bus.Ddr) bool {
    if (ddr.bytes() < mc.VMODE_FROM_TOP) return false;
    const w = ddr.words[(ddr.bytes() - mc.VMODE_FROM_TOP) / 4];
    return w & mc.VMODE_TAG_MASK == mc.VMODE_TAG and w & mc.VMODE_DESK != 0;
}

pub fn isMouse(ev_type: u16, code: u16) bool {
    return ev_type == EV_REL or (ev_type == EV_KEY and code >= BTN_LEFT and code <= BTN_MOUSE_LAST);
}

// Where the position may go, in 1/SCALE_ONE pixels: where the cart draws in the plane modes
// (the firmware's box words, map_cart.zig VBOX_*: GEM's visible window, pt2's 320x255 picture), the
// 640x480 picture in the desk mode (map.zig PTR_DESK_*), where nothing is drawn round it.
pub const Box = struct { x0: i32, y0: i32, x1: i32, y1: i32 };
/// No box words (an older firmware, no frame yet): the whole raster, as before the box, so a cart
/// drawn over the borders is never cut off.
pub const WHOLE = pixels(0, 0, map.PTR_WIDTH, map.PTR_HEIGHT);

fn pixels(x0: u32, y0: u32, x1: u32, y1: u32) Box { // ends exclusive, in pixels
    return .{
        .x0 = @as(i32, @intCast(x0)) * SCALE_ONE,
        .y0 = @as(i32, @intCast(y0)) * SCALE_ONE,
        .x1 = @as(i32, @intCast(x1)) * SCALE_ONE - 1,
        .y1 = @as(i32, @intCast(y1)) * SCALE_ONE - 1,
    };
}

/// The firmware's box words (cycles/bptrbox.h): where the cart's picture is, or null for an
/// untagged word or a box that is empty or off the raster.
pub fn planeBox(ddr: bus.Ddr) ?Box {
    const xs = span(ddr, mc.VBOX_X_FROM_TOP, mc.VBOX_X_TAG, map.PTR_WIDTH) orelse return null;
    const ys = span(ddr, mc.VBOX_Y_FROM_TOP, mc.VBOX_Y_TAG, map.PTR_HEIGHT) orelse return null;
    return pixels(xs[0], ys[0], xs[1], ys[1]);
}

fn span(ddr: bus.Ddr, from_top: u32, tag: u32, end: u32) ?[2]u32 {
    if (ddr.bytes() < from_top) return null;
    const w = ddr.words[(ddr.bytes() - from_top) / 4];
    if (w & mc.VBOX_TAG_MASK != tag) return null;
    const lo = w & mc.VBOX_FIELD_MASK;
    const hi = w >> mc.VBOX_HI_SHIFT & mc.VBOX_FIELD_MASK;
    return if (lo < hi and hi <= end) .{ lo, hi } else null;
}

const DESK = Box{
    .x0 = @as(i32, map.PTR_BORDER_X) * SCALE_ONE,
    .y0 = @as(i32, map.PTR_BORDER_Y) * SCALE_ONE,
    .x1 = @as(i32, map.PTR_BORDER_X + map.PTR_DESK_WIDTH) * SCALE_ONE - 1,
    .y1 = @as(i32, map.PTR_BORDER_Y + map.PTR_DESK_HEIGHT) * SCALE_ONE - 1,
};

pub const Mouse = struct {
    // Sub-pixel position, so a scale below one pixel a count still moves.
    // The middle of the visible window (also the raster's), on a pixel's edge.
    fx: i32 = (map.PTR_BORDER_X + (map.PTR_WIDTH - 2 * map.PTR_BORDER_X) / 2) * SCALE_ONE,
    fy: i32 = (map.PTR_BORDER_Y + (map.PTR_HEIGHT - 2 * map.PTR_BORDER_Y) / 2) * SCALE_ONE,
    scale: i32 = SCALE_ONE,
    held: u32 = 0, // physical buttons down, bit (code - BTN_LEFT)
    last_press_ms: ?i64 = null,
    double: bool = false, // the release that ends a double-click owes the pulse
    dirty: bool = false,
    sent: ?u32 = null, // the last word written, to skip a sub-pixel nudge
    desk: bool = false, // the cart is in the desk mode (map_cart.zig VMODE_DESK): 640x480 at 1:1
    planes: Box = WHOLE, // where the plane modes draw (planeBox)

    pub fn x(self: Mouse) u32 {
        return @intCast(@divFloor(self.fx, SCALE_ONE));
    }

    pub fn y(self: Mouse) u32 {
        return @intCast(@divFloor(self.fy, SCALE_ONE));
    }

    pub fn word(self: Mouse, buttons: u32) u32 {
        return self.x() << map.PTR_X_SHIFT | self.y() << map.PTR_Y_SHIFT | buttons << map.PTR_BTN_SHIFT;
    }

    /// The cart's screen mode (the firmware's VMODE word): a change keeps the pointer inside the
    /// new mode's box and sends the clamped position at the next report.
    pub fn setDesk(self: *Mouse, on: bool) void {
        if (on == self.desk) return;
        self.desk = on;
        self.clampIn();
    }

    /// Where the cart's planes draw (planeBox; null: the whole raster): a change pulls a pointer
    /// left outside the new box in, at the next report, as a mode change does.
    pub fn setPlaneBox(self: *Mouse, b: ?Box) void {
        const nb = b orelse WHOLE;
        if (std.meta.eql(nb, self.planes)) return;
        self.planes = nb;
        if (!self.desk) self.clampIn();
    }

    fn clampIn(self: *Mouse) void {
        const b = self.box();
        self.fx = std.math.clamp(self.fx, b.x0, b.x1);
        self.fy = std.math.clamp(self.fy, b.y0, b.y1);
        self.dirty = true;
    }

    fn box(self: Mouse) Box {
        return if (self.desk) DESK else self.planes;
    }

    /// Fold one mouse event in; the words to write come out at the next SYN_REPORT (`flush`).
    pub fn update(self: *Mouse, ev_type: u16, code: u16, value: i32, ms: i64) void {
        const b = self.box();
        switch (ev_type) {
            // A ZigMachine row is twice as tall as its column is wide (640x200 on
            // a 4:3 screen), so y moves half as many rows a count as x moves columns;
            // the desk's pixels are square, so there it moves as many.
            EV_REL => switch (code) {
                REL_X => self.fx = std.math.clamp(self.fx +| value *| self.scale, b.x0, b.x1),
                REL_Y => self.fy = std.math.clamp(self.fy +| @divTrunc(value *| self.scale, @as(i32, if (self.desk) 1 else 2)), b.y0, b.y1),
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
