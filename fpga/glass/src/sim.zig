// A simulated glass: the register block as rtl/glass/zm_glass_regs.v behaves,
// a fake DDR window, and a stand-in for the cart CPU's firmware that reports
// BOOTING then RUNNING (or a trap, or nothing) once it is let out of reset.
// The ARM program runs against this on a desktop exactly as on the board.
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");

pub const CartModel = enum { boots, traps, silent };

pub const Glass = struct {
    ctrl: u32 = 0,
    load_base: u32 = map.DDR_CART_BASE,
    load_size: u32 = 0,
    joy: u32 = 0,
    osd_fg: u32 = 0xFFFFFF,
    osd_bg: u32 = 0,
    scratch: u32 = 0,
    keys: [map.KEY_DEPTH]u32 = undefined,
    key_len: u32 = 0,
    overflow: bool = false,
    text: [map.OSD_CHARS]u32 = [_]u32{0} ** map.OSD_CHARS,
    cart_state: u32 = map.CART_RESET,
    cart_beat: u32 = 0,
    // The stand-in firmware: how it behaves, and how many STATE reads it takes to boot.
    cart: CartModel = .boots,
    boot_reads: u32 = 3,
    reads_since_run: u32 = 0,
    resets: u32 = 0,

    pub fn regs(self: *Glass) bus.Regs {
        return .{ .ctx = self, .read_fn = readThunk, .write_fn = writeThunk };
    }

    fn readThunk(ctx: *anyopaque, offset: u32) u32 {
        const self: *Glass = @ptrCast(@alignCast(ctx));
        return self.read(offset);
    }

    fn writeThunk(ctx: *anyopaque, offset: u32, value: u32) void {
        const self: *Glass = @ptrCast(@alignCast(ctx));
        self.write(offset, value);
    }

    fn running(self: *const Glass) bool {
        return self.ctrl & map.CTRL_RUN != 0;
    }

    pub fn read(self: *Glass, offset: u32) u32 {
        if (offset >= 0x1000) return 0; // the OSD text is write-only, the rest unmapped
        return switch (offset) {
            map.REG_ID => map.ID_VALUE,
            map.REG_VERSION => map.VERSION,
            map.REG_CTRL => self.ctrl,
            map.REG_STATUS => self.status(),
            map.REG_CART_STATE => self.cartState(),
            map.REG_CART_BEAT => self.cart_beat,
            map.REG_LOAD_BASE => self.load_base,
            map.REG_LOAD_SIZE => self.load_size,
            map.REG_KEY_LEVEL => self.key_len,
            map.REG_JOY => self.joy,
            map.REG_OSD_FG => self.osd_fg,
            map.REG_OSD_BG => self.osd_bg,
            map.REG_SCRATCH => self.scratch,
            else => 0,
        };
    }

    fn status(self: *const Glass) u32 {
        var s: u32 = 0;
        if (self.running()) s |= map.ST_RUNNING;
        if (self.key_len == map.KEY_DEPTH) s |= map.ST_KEY_FULL;
        if (self.overflow) s |= map.ST_KEY_OVERFLOW;
        return s;
    }

    // The stand-in firmware advances one step per poll, so a loader that never
    // polls never sees it boot.
    fn cartState(self: *Glass) u32 {
        if (!self.running()) return map.CART_RESET;
        self.reads_since_run += 1;
        if (self.reads_since_run < self.boot_reads) return map.CART_BOOTING;
        self.cart_state = switch (self.cart) {
            .boots => map.CART_RUNNING,
            .traps => map.CART_TRAPPED | (5 << 8),
            .silent => map.CART_BOOTING,
        };
        if (self.cart == .boots) self.cart_beat += 1;
        return self.cart_state;
    }

    pub fn write(self: *Glass, offset: u32, value: u32) void {
        if (offset >= map.OFF_OSD_TEXT and offset < map.OFF_OSD_TEXT + 4 * map.OSD_CHARS) {
            self.text[(offset - map.OFF_OSD_TEXT) / 4] = value & 0x1FF;
            return;
        }
        switch (offset) {
            map.REG_CTRL => self.writeCtrl(value),
            map.REG_LOAD_BASE => self.load_base = value,
            map.REG_LOAD_SIZE => self.load_size = value,
            map.REG_KEY_PUSH => self.push(value),
            map.REG_JOY => self.joy = value & 0xFF,
            map.REG_OSD_FG => self.osd_fg = value & 0xFFFFFF,
            map.REG_OSD_BG => self.osd_bg = value & 0xFFFFFF,
            map.REG_SCRATCH => self.scratch = value,
            else => {},
        }
    }

    fn writeCtrl(self: *Glass, value: u32) void {
        if (value & map.CTRL_KEY_FLUSH != 0) {
            self.key_len = 0;
            self.overflow = false;
        }
        const was = self.running();
        self.ctrl = value & (map.CTRL_RUN | map.CTRL_OSD);
        if (was and !self.running()) self.resets += 1;
        if (!self.running()) {
            self.cart_state = map.CART_RESET;
            self.cart_beat = 0;
            self.reads_since_run = 0;
        }
    }

    pub fn push(self: *Glass, event: u32) void {
        if (self.key_len == map.KEY_DEPTH) {
            self.overflow = true;
            return;
        }
        self.keys[self.key_len] = event;
        self.key_len += 1;
    }

    /// What the cart CPU's firmware would pop next (tests).
    pub fn pop(self: *Glass) ?u32 {
        if (self.key_len == 0) return null;
        const v = self.keys[0];
        std.mem.copyForwards(u32, self.keys[0 .. self.key_len - 1], self.keys[1..self.key_len]);
        self.key_len -= 1;
        return v;
    }
};

test "the simulated block keeps the RTL's rules" {
    var g = Glass{};
    const r = g.regs();
    try std.testing.expectEqual(map.ID_VALUE, r.read(map.REG_ID));
    try std.testing.expectEqual(@as(u32, 0), r.read(map.REG_STATUS) & map.ST_RUNNING);
    for (0..map.KEY_DEPTH + 1) |i| r.write(map.REG_KEY_PUSH, @intCast(i));
    try std.testing.expect(r.read(map.REG_STATUS) & map.ST_KEY_OVERFLOW != 0);
    try std.testing.expectEqual(@as(?u32, 0), g.pop());
    r.write(map.REG_CTRL, map.CTRL_KEY_FLUSH);
    try std.testing.expectEqual(@as(u32, 0), r.read(map.REG_KEY_LEVEL));
    try std.testing.expectEqual(@as(u32, 0), r.read(map.REG_CTRL));
    r.write(map.REG_CTRL, map.CTRL_RUN);
    try std.testing.expectEqual(map.CART_BOOTING, r.read(map.REG_CART_STATE));
}
