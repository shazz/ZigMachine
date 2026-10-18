// --------------------------------------------------------------------------
// Row blits with the registers left loaded.
//
// zg.Blitter sets the whole register block for every op, which is right for a
// handful of blits and wrong for hundreds: on ZIGGY each register store is a
// blocking bus write (~24-31 cycles), so a 12-store setup per row costs more
// than the 1 clock/px the blitter then needs. The block keeps its values
// between ops (machine/blitter.zig execute() only writes CYCLES and STATUS), so
// a screen that blits the SAME kind of op many times sets the constants once
// (`open`) and then stores only what moved: this struct remembers the last
// X0/Y0/W/H it wrote and skips equal ones.
//
// Source: an absolute address in cart RAM (CON2.SRC_ABS, like blitImage), with a
// pitch of the caller's choosing. A pitch of 1 makes every row start one pixel
// after the last (a diagonal), a pitch of 0 repeats one row.
//
// Nothing else may touch the blitter between open() and the last blit(): a
// zg.Blitter call, or a lib effect that blits, reloads the registers. Re-open.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const zg = @import("zigos");

pub const Rows = struct {
    base: usize,
    x0: i16 = -1,
    y0: i16 = -1,
    w: u16 = 0,
    h: u16 = 0,

    /// Load the constant registers: destination plane `fb`, source pitch
    /// `pitch`, and `key` (a source pixel equal to it is not drawn; null copies
    /// every pixel).
    pub fn open(fb: *zg.LogicalFB, pitch: u16, key: ?u8) Rows {
        const base: usize = @intCast(hw.hwVideoBase());
        var r = Rows{ .base = base };
        r.w32(hw.BLIT_D_BASE, @intCast(@intFromPtr(fb.fb) - base));
        r.w16(hw.BLIT_D_STRIDE, fb.stride);
        r.w8(hw.BLIT_CON2, hw.CON2_SRC_ABS);
        r.w16(hw.BLIT_B_STRIDE, pitch);
        r.w8(hw.BLIT_CON, if (key != null) hw.CON_USEB | hw.CON_KEY_EN else hw.CON_USEB);
        r.w8(hw.BLIT_MINTERM, hw.MT_B);
        r.w8(hw.BLIT_COLOR_KEY, key orelse 0);
        return r;
    }

    /// Copy the w x h block at `src` (cart RAM address) to (dx,dy) of the plane.
    pub fn blit(self: *Rows, src: usize, dx: i16, dy: i16, w: u16, h: u16) void {
        self.w32(hw.BLIT_B_BASE, @intCast(src));
        if (dx != self.x0) {
            self.w16(hw.BLIT_X0, @bitCast(dx));
            self.x0 = dx;
        }
        if (dy != self.y0) {
            self.w16(hw.BLIT_Y0, @bitCast(dy));
            self.y0 = dy;
        }
        if (w != self.w) {
            self.w16(hw.BLIT_W, w);
            self.w = w;
        }
        if (h != self.h) {
            self.w16(hw.BLIT_H, h);
            self.h = h;
        }
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_BLIT);
        hw.hwBlit();
    }

    inline fn w8(self: *Rows, off: usize, v: u8) void {
        @as(*u8, @ptrFromInt(self.base + off)).* = v;
    }
    inline fn w16(self: *Rows, off: usize, v: u16) void {
        @as(*u16, @ptrFromInt(self.base + off)).* = v;
    }
    inline fn w32(self: *Rows, off: usize, v: u32) void {
        @as(*u32, @ptrFromInt(self.base + off)).* = v;
    }
};
