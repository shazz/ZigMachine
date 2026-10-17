// A simulated glass: the register block as rtl/glass/zm_glass_regs.v behaves,
// and a stand-in for the cart CPU's firmware that reports BOOTING then RUNNING
// (or a trap, or nothing) once let out of reset, warm boots as glass_boot.c
// decides. The ARM program runs against this exactly as on the board.
const std = @import("std");
const map = @import("map.zig");
const map_cart = @import("map_cart.zig");
const bus = @import("bus.zig");

pub const CartModel = enum { boots, traps, silent };
pub const FW_VERSION: u32 = 0x00_01_00; // what the stand-in firmware reports, 0.1.0 (glass_boot.h)

pub const Glass = struct {
    ctrl: u32 = 0,
    load_base: u32 = map.LOAD_BASE_RESET,
    load_size: u32 = 0,
    joy: u32 = 0,
    osd_fg: u32 = 0xFFFFFF,
    osd_bg: u32 = 0,
    osd_pos: u32 = map.OSD_POS_RESET,
    osd_pos_writes: u32 = 0, // an older PL has no REG_OSD_POS: the glass must not need it
    version: u32 = map.VERSION, // set lower to stand in for an older PL
    scratch: u32 = 0,
    keys: [map.KEY_DEPTH]u32 = undefined,
    key_len: u32 = 0,
    overflow: bool = false,
    text: [map.OSD_CHARS]u32 = [_]u32{0} ** map.OSD_CHARS,
    cart_state: u32 = map.CART_RESET,
    cart_beat: u32 = 0,
    ptr: u32 = 0, // x, y and the held buttons, as the ARM wrote them
    ptr_latch: u32 = 0, // buttons pressed since the cart's last ack
    ptr_seq: u32 = 0,
    // The stand-in firmware: how it behaves, and how many STATE reads it takes to boot.
    cart: CartModel = .boots,
    trap_code: u32 = 5, // what .traps reports (a wasm2c trap; or TRAP_CART_ABI, map_cart.zig)
    boot_reads: u32 = 3,
    reads_since_run: u32 = 0,
    resets: u32 = 0,
    audio_vol: u32 = map.AUDIO_VOL_RESET,
    marked: bool = false, // a cold boot marked the cart's memory (glass_boot_mark)
    warm_boots: u32 = 0,
    stuck: bool = false, // a CPU that never leaves RUNNING: the loader's WontStop
    request: u32 = 0, // a booted stand-in asks for a cart swap: CART_REQUEST (map_cart.zig)

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
            map.REG_VERSION => self.version,
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
            map.REG_POINTER => self.pointer(),
            map.REG_AUDIO_VOL => self.audio_vol,
            map.REG_OSD_POS => self.osd_pos,
            else => 0,
        };
    }

    fn status(self: *const Glass) u32 {
        var s: u32 = 0;
        if (self.running() or self.stuck) s |= map.ST_RUNNING;
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
        const warm = self.ctrl & map.CTRL_WARM != 0;
        if (warm and !self.marked) return map.CART_TRAPPED | map.TRAP_WARM_LOST << map.CART_ARG_SHIFT;
        self.cart_state = switch (self.cart) {
            .boots => if (self.request != 0) map_cart.CART_REQUEST | self.request << map.CART_ARG_SHIFT else map.CART_RUNNING | FW_VERSION << map.CART_ARG_SHIFT,
            .traps => map.CART_TRAPPED | self.trap_code << map.CART_ARG_SHIFT,
            .silent => map.CART_BOOTING,
        };
        if (self.cart == .boots) {
            if (self.cart_beat == 0 and warm) self.warm_boots += 1;
            self.marked = true;
            self.cart_beat += 1;
        }
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
            map.REG_LOAD_SIZE => { // a cold load rewrote the window: no mark survives it
                self.load_size = value;
                self.marked = false;
            },
            map.REG_KEY_PUSH => self.push(value),
            map.REG_JOY => self.joy = value & 0xFF,
            map.REG_OSD_FG => self.osd_fg = value & 0xFFFFFF,
            map.REG_OSD_BG => self.osd_bg = value & 0xFFFFFF,
            map.REG_SCRATCH => self.scratch = value,
            map.REG_POINTER => self.pointerWrite(value),
            map.REG_AUDIO_VOL => self.audio_vol = value & (map.AUDIO_MUTE | map.AUDIO_VOL_MASK),
            map.REG_OSD_POS => {
                self.osd_pos = value & (map.OSD_POS_X_MASK << map.OSD_POS_X_SHIFT | map.OSD_POS_Y_MASK << map.OSD_POS_Y_SHIFT);
                self.osd_pos_writes += 1;
            },
            else => {},
        }
    }

    fn writeCtrl(self: *Glass, value: u32) void {
        if (value & map.CTRL_KEY_FLUSH != 0) {
            self.key_len = 0;
            self.overflow = false;
        }
        const was = self.running();
        const stats = if (self.version >= map.VERSION_OSD_STATS) map.CTRL_OSD_STATS else 0;
        self.ctrl = value & (map.CTRL_RUN | map.CTRL_OSD | map.CTRL_WARM | stats);
        if (was and !self.running()) self.resets += 1;
        if (!self.running()) {
            self.cart_state = map.CART_RESET;
            self.cart_beat = 0;
            self.reads_since_run = 0;
            self.request = 0; // the next cart starts without one
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

    fn pointerWrite(self: *Glass, value: u32) void {
        self.ptr = value & ((1 << map.PTR_SEQ_SHIFT) - 1);
        self.ptr_latch |= (value >> map.PTR_BTN_SHIFT) & map.PTR_BTN_MASK;
        self.ptr_seq = (self.ptr_seq + 1) & map.PTR_SEQ_MASK;
    }

    /// The word the cart CPU reads (and the ARM reads back): held | latched buttons, SEQ.
    pub fn pointer(self: *const Glass) u32 {
        const btn = (self.ptr >> map.PTR_BTN_SHIFT | self.ptr_latch) & map.PTR_BTN_MASK;
        const keep = self.ptr & ~(map.PTR_BTN_MASK << map.PTR_BTN_SHIFT);
        return keep | btn << map.PTR_BTN_SHIFT | self.ptr_seq << map.PTR_SEQ_SHIFT;
    }

    /// The firmware acks the SEQ it delivered (rtl/glass/zm_glass_ptr.v's rules).
    pub fn pointerAck(self: *Glass, seq: u32) void {
        if (seq != self.ptr_seq) return; // stale: the ARM wrote since
        const dropped = self.ptr_latch & ~(self.ptr >> map.PTR_BTN_SHIFT);
        self.ptr_latch = 0;
        if (dropped & map.PTR_BTN_MASK != 0) self.ptr_seq = (self.ptr_seq + 1) & map.PTR_SEQ_MASK;
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
