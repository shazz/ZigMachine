// --------------------------------------------------------------------------
// ZigOS's own CHISEL ops: a plane clear (clearFrameBuffer), a filled box
// (blit.Dst.fill) and a copied box (blit.blit's copy ink, keyed or not) as
// blitter ops instead of CPU stores, with the same bytes as a result. On the
// board a store is a blocking DDR write (a memset ~60 cycles a word, a keyed
// byte loop ~20 cycles a pixel) and CHISEL ~1-2 cycles a pixel.
// effects/chisel_clear.zig decides which ops are byte-identical, and why.
//
// Transparent to the cart: a scene may be between loading its own blitter
// registers and firing them (stniccc/gpu.zig loads D_BASE once a frame), so
// every register an op writes is read first and put back after (only those
// that differ are stored back). A loaded halftone pattern would dither a fill,
// so then fills fall back to the CPU.
// --------------------------------------------------------------------------
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
    if (!fillRect(base, fb, stride, stride, rows, v)) @memset(fb[0 .. @as(usize, rows) * stride], v);
}

/// Fill the `w` x `rows` box whose top-left byte is `at` (rows `stride` apart)
/// with `v`. False, and nothing written, when CHISEL cannot do it identically.
pub fn fillRect(base: usize, at: [*]u8, stride: u16, w: u16, rows: u16, v: u8) bool {
    const off = regionOffset(base, at) orelse return false;
    if (!plan.usable(G, off, stride, w, rows) or halftoneLoaded(base)) return false;
    const r = Reg{ .base = base };
    const saved = Saved.read(r);
    r.w16(hw.BLIT_D_STRIDE, stride);
    r.w8(hw.BLIT_CON, 0); // no CLIP_EN
    r.w8(hw.BLIT_CON2, 0); // no FILL_MT, SRC_ABS or forced halftone
    r.w8(hw.BLIT_COLOR, v);
    run(r, off, stride, w, rows, hw.BLIT_CMD_FILL, null, 0);
    saved.restore(r);
    return true;
}

/// Copy the `w` x `rows` box at `src` (rows `src_stride` apart) to the box at
/// `at` (rows `stride` apart); source pixels equal to `key` are left out. False,
/// and nothing written, when CHISEL cannot do it identically: the destination
/// is not a plane, the source is outside the machine's readable windows, or
/// the two overlap (the CPU's row order would then be part of the result).
pub fn copyRect(base: usize, at: [*]u8, stride: u16, src: [*]const u8, src_stride: u16, w: u16, rows: u16, key: ?u8) bool {
    const off = regionOffset(base, at) orelse return false;
    if (!plan.usable(G, off, stride, w, rows) or w > src_stride) return false;
    const s0 = @intFromPtr(src);
    const s1 = s0 + (@as(usize, rows) - 1) * src_stride + w;
    const d0 = @intFromPtr(at);
    const d1 = d0 + (@as(usize, rows) - 1) * stride + w;
    if (s0 < d1 and d0 < s1) return false;
    if (!readable(base, s0, s1)) return false;
    const r = Reg{ .base = base };
    const saved = Saved.read(r);
    r.w16(hw.BLIT_D_STRIDE, stride);
    r.w8(hw.BLIT_CON, if (key != null) hw.CON_USEB | hw.CON_KEY_EN else hw.CON_USEB);
    r.w8(hw.BLIT_CON2, hw.CON2_SRC_ABS);
    r.w8(hw.BLIT_MINTERM, hw.MT_B);
    r.w8(hw.BLIT_COLOR_KEY, key orelse 0);
    r.w16(hw.BLIT_B_STRIDE, src_stride);
    run(r, off, stride, w, rows, hw.BLIT_CMD_BLIT, s0, src_stride);
    saved.restore(r);
    return true;
}

/// The op in runs of at most the rows the machine's clip allows for `stride`,
/// each run's D (and B) moved down to its first row, X0 = Y0 = 0.
fn run(r: Reg, off: usize, stride: u16, w: u16, rows: u16, cmd: u8, src: ?usize, src_stride: u16) void {
    r.w32(hw.BLIT_X0, 0);
    var i: usize = 0;
    var first: usize = 0;
    while (plan.fillAt(G, off, stride, rows, i)) |f| : (i += 1) {
        r.w32(hw.BLIT_D_BASE, @intCast(f.off));
        if (src) |s| r.w32(hw.BLIT_B_BASE, @intCast(s + first * src_stride));
        r.w32(hw.BLIT_W, @as(u32, w) | @as(u32, f.h) << 16); // W, H
        r.w8(hw.BLIT_COMMAND, cmd);
        hw.hwBlit();
        first += f.h;
    }
}

fn regionOffset(base: usize, at: [*]const u8) ?usize {
    const a = @intFromPtr(at);
    if (base == 0 or a < base) return null;
    return a - base;
}

/// [s0, s1) inside one of the windows machine/blitter.zig lets SRC_ABS read.
fn readable(base: usize, s0: usize, s1: usize) bool {
    const wins = [_][2]usize{
        .{ hw.CART_RAM_BASE, hw.CART_RAM_TOP },
        .{ base, base + G.region },
        .{ hw.ROM_RAM_BASE, hw.ROM_RAM_TOP },
    };
    for (wins) |win| if (s0 >= win[0] and s1 <= win[1]) return true;
    return false;
}

fn halftoneLoaded(base: usize) bool {
    const p: *const volatile [8]u32 = @ptrFromInt(base + hw.BLIT_HALFTONE);
    var any: u32 = 0;
    for (0..8) |i| any |= p[i];
    return any != 0;
}

const Reg = struct {
    base: usize,
    fn ptr(r: Reg, comptime T: type, off: usize) *volatile T {
        return @ptrFromInt(r.base + off);
    }
    fn w8(r: Reg, off: usize, v: u8) void {
        r.ptr(u8, off).* = v;
    }
    fn w16(r: Reg, off: usize, v: u16) void {
        r.ptr(u16, off).* = v;
    }
    fn w32(r: Reg, off: usize, v: u32) void {
        r.ptr(u32, off).* = v;
    }
};

/// Every register a ZigOS CHISEL op writes, as the cart left it. Inline, so the
/// values stay in locals: a struct on the stack is a store per field, and every
/// store is a blocking DDR write on the board.
const Saved = struct {
    const B8 = [_]usize{ hw.BLIT_COMMAND, hw.BLIT_MINTERM, hw.BLIT_CON, hw.BLIT_COLOR, hw.BLIT_COLOR_KEY, hw.BLIT_CON2 };
    const B16 = [_]usize{ hw.BLIT_D_STRIDE, hw.BLIT_B_STRIDE };
    const B32 = [_]usize{ hw.BLIT_D_BASE, hw.BLIT_B_BASE, hw.BLIT_W, hw.BLIT_X0 }; // W|H, X0|Y0
    b8: [B8.len]u8,
    b16: [B16.len]u16,
    b32: [B32.len]u32,

    inline fn read(r: Reg) Saved {
        var s: Saved = undefined;
        inline for (B8, 0..) |o, i| s.b8[i] = r.ptr(u8, o).*;
        inline for (B16, 0..) |o, i| s.b16[i] = r.ptr(u16, o).*;
        inline for (B32, 0..) |o, i| s.b32[i] = r.ptr(u32, o).*;
        return s;
    }

    /// Put back what changed. The current values all went out through stores of
    /// our own, so a register that already holds the cart's value needs none.
    inline fn restore(s: Saved, r: Reg) void {
        inline for (B8, 0..) |o, i| if (r.ptr(u8, o).* != s.b8[i]) r.w8(o, s.b8[i]);
        inline for (B16, 0..) |o, i| if (r.ptr(u16, o).* != s.b16[i]) r.w16(o, s.b16[i]);
        inline for (B32, 0..) |o, i| if (r.ptr(u32, o).* != s.b32[i]) r.w32(o, s.b32[i]);
    }
};
