// --------------------------------------------------------------------------
// clearFrameBuffer on CHISEL: a whole-plane clear as blitter FILLs instead of a
// CPU @memset, same bytes (effects/chisel_clear.zig says which fills, and why).
//
// Transparent to the cart: a scene may be between setting up its own blitter
// registers and firing them (stniccc/gpu.zig sets D_BASE once per frame), so
// every register the fill writes is read first and put back after. A loaded
// halftone pattern would dither the fill, so then the clear stays a memset.
// --------------------------------------------------------------------------
const std = @import("std");
const hw = @import("hardware");
const plan = @import("effects/chisel_clear.zig");

const G = plan.Geometry{
    .vram = hw.OFF_VRAM,
    .region = hw.OFF_PFB + @as(usize, hw.RASTER_WIDTH) * hw.RASTER_HEIGHT * 4, // REGION_BYTES (memmap.zig)
    .full_stride = hw.STRIDE_FULLSCREEN,
    .full_h = hw.PHYSICAL_HEIGHT,
    .normal_h = hw.HEIGHT,
};

/// Clear `rows` x `stride` bytes at `fb` (inside the video region at `base`)
/// to `v`. `base` 0 (ZigOS not initialised) falls back to the memset.
pub fn clear(base: usize, fb: [*]u8, stride: u16, rows: u16, v: u8) void {
    const n = @as(usize, rows) * stride;
    const addr = @intFromPtr(fb);
    if (base == 0 or addr < base or !plan.usable(G, addr - base, stride, rows) or halftoneLoaded(base)) {
        @memset(fb[0..n], v);
        return;
    }
    const saved = Saved.read(base);
    const r = Reg{ .base = base };
    r.w16(hw.BLIT_D_STRIDE, stride);
    r.w8(hw.BLIT_CON, 0); // no CLIP_EN
    r.w8(hw.BLIT_CON2, 0); // no FILL_MT, SRC_ABS or forced halftone
    r.w8(hw.BLIT_COLOR, v);
    r.w32(hw.BLIT_X0, 0); // X0 = Y0 = 0
    var i: usize = 0;
    while (plan.fillAt(G, addr - base, stride, rows, i)) |f| : (i += 1) {
        r.w32(hw.BLIT_D_BASE, @intCast(f.off));
        r.w32(hw.BLIT_W, @as(u32, stride) | @as(u32, f.h) << 16); // W, H
        r.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_FILL);
        hw.hwBlit();
    }
    saved.write(base);
}

fn halftoneLoaded(base: usize) bool {
    const p: *const [8]u32 = @ptrFromInt(base + hw.BLIT_HALFTONE);
    var any: u32 = 0;
    for (p) |w| any |= w;
    return any != 0;
}

const Reg = struct {
    base: usize,
    fn w8(r: Reg, off: usize, v: u8) void {
        @as(*volatile u8, @ptrFromInt(r.base + off)).* = v;
    }
    fn w16(r: Reg, off: usize, v: u16) void {
        @as(*volatile u16, @ptrFromInt(r.base + off)).* = v;
    }
    fn w32(r: Reg, off: usize, v: u32) void {
        @as(*volatile u32, @ptrFromInt(r.base + off)).* = v;
    }
    fn r8(r: Reg, off: usize) u8 {
        return @as(*volatile u8, @ptrFromInt(r.base + off)).*;
    }
    fn r16(r: Reg, off: usize) u16 {
        return @as(*volatile u16, @ptrFromInt(r.base + off)).*;
    }
    fn r32(r: Reg, off: usize) u32 {
        return @as(*volatile u32, @ptrFromInt(r.base + off)).*;
    }
};

/// The registers the fill writes, as the cart left them.
const Saved = struct {
    command: u8,
    con: u8,
    con2: u8,
    color: u8,
    d_base: u32,
    d_stride: u16,
    wh: u32,
    xy: u32,

    fn read(base: usize) Saved {
        const r = Reg{ .base = base };
        return .{
            .command = r.r8(hw.BLIT_COMMAND),
            .con = r.r8(hw.BLIT_CON),
            .con2 = r.r8(hw.BLIT_CON2),
            .color = r.r8(hw.BLIT_COLOR),
            .d_base = r.r32(hw.BLIT_D_BASE),
            .d_stride = r.r16(hw.BLIT_D_STRIDE),
            .wh = r.r32(hw.BLIT_W),
            .xy = r.r32(hw.BLIT_X0),
        };
    }

    fn write(s: Saved, base: usize) void {
        const r = Reg{ .base = base };
        r.w8(hw.BLIT_COMMAND, s.command);
        r.w8(hw.BLIT_CON, s.con);
        r.w8(hw.BLIT_CON2, s.con2);
        r.w8(hw.BLIT_COLOR, s.color);
        r.w32(hw.BLIT_D_BASE, s.d_base);
        r.w16(hw.BLIT_D_STRIDE, s.d_stride);
        r.w32(hw.BLIT_W, s.wh);
        r.w32(hw.BLIT_X0, s.xy);
    }
};
