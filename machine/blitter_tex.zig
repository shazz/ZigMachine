// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter: the texture ops of CHISEL v2 (1.10.0).
//   AFFINE: textured spans from a list (Mode 7 floors, rotozooms, textured polygons)
//   MAP:    a box whose every pixel takes its texel from a (u, v) map (tunnels)
// Both read the texture through channel A and combine the texel as B with the
// destination: D = LF(0, texel, D). See memmap.zig "CHISEL v2" and
// docs/BLITTER_HW_SPEC.md §4.5-4.6.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const regs = @import("blitter_regs.zig");
const check = @import("blitter_check.zig");
const Clip = regs.Clip;

// The texture and how a texel is drawn, decoded once an op. Null: refused.
const Tex = struct {
    base: [*]const u8,
    stride: usize,
    umask: u16,
    vmask: u16,
    clip: bool, // TEX_CLIP: past a mask is not drawn (else wrapped)
    mt: u8,
    key: u8,
    key_en: bool,

    fn load(con: u8, con2: u8) ?Tex {
        const umask = regs.r16(memmap.BLIT_U_MASK);
        const vmask = regs.r16(memmap.BLIT_V_MASK);
        const stride = regs.r16(memmap.BLIT_A_STRIDE);
        const abs = con2 & memmap.CON2_SRC_ABS != 0;
        // the whole (U_MASK+1) x (V_MASK+1) texture, in u32 since a mask may be 0xFFFF
        if (!texReadable(abs, regs.r32(memmap.BLIT_A_BASE), stride, @as(u32, umask) + 1, @as(u32, vmask) + 1)) return null;
        const base: [*]const u8 = if (abs) @ptrFromInt(regs.r32(memmap.BLIT_A_BASE)) else regs.region() + regs.r32(memmap.BLIT_A_BASE);
        return .{
            .base = base,
            .stride = stride,
            .umask = umask,
            .vmask = vmask,
            .clip = con2 & memmap.CON2_TEX_CLIP != 0,
            .mt = regs.r8(memmap.BLIT_MINTERM),
            .key = regs.r8(memmap.BLIT_COLOR_KEY),
            .key_en = con & memmap.CON_KEY_EN != 0,
        };
    }

    // Draw texel (u, v) at d[di]; true when a pixel was written (for CYCLES).
    fn put(t: Tex, d: [*]u8, di: usize, u: u16, v: u16) bool {
        if (t.clip and (u > t.umask or v > t.vmask)) return false;
        const texel = t.base[@as(usize, v & t.vmask) * t.stride + (u & t.umask)];
        if (t.key_en and texel == t.key) return false;
        d[di] = if (t.mt == memmap.MT_B) texel else regs.applyMinterm(0, texel, d[di], t.mt);
        return true;
    }
};

// check.source()'s rule for a texture whose size may reach 65536 a side.
fn texReadable(abs: bool, base: u32, stride: u16, w: u32, h: u32) bool {
    const lo: u64 = if (abs) base else @as(u64, memmap.HW_VIDEO_BASE) + base;
    const hi: u64 = lo + @as(u64, h - 1) * stride + w;
    return inWindow(lo, hi, abs);
}

// [lo, hi) in the video region, or (absolute only) in cart RAM or the ROM window.
fn inWindow(lo: u64, hi: u64, abs: bool) bool {
    if (lo >= memmap.HW_VIDEO_BASE and hi <= memmap.HW_VIDEO_BASE + memmap.REGION_BYTES) return true;
    return abs and inAux(lo, hi);
}

// Where a span list or a map may live: cart RAM or the ROM window, which CHISEL never writes.
fn inAux(lo: u64, hi: u64) bool {
    return (lo >= memmap.CART_RAM_BASE and hi <= memmap.CART_RAM_TOP) or
        (lo >= memmap.ROM_RAM_BASE and hi <= memmap.ROM_RAM_TOP);
}

inline fn rd16(p: [*]const u8) u16 {
    return std.mem.readInt(u16, p[0..2], .little);
}
inline fn rd32(p: [*]const u8) u32 {
    return std.mem.readInt(u32, p[0..4], .little);
}

pub fn doAffine(d: [*]u8, ds: u16, c: Clip, con: u8, con2: u8, cost: *u32) void {
    const t = Tex.load(con, con2) orelse return;
    const n: u64 = regs.r16(memmap.BLIT_SPAN_COUNT);
    const lo: u64 = regs.r32(memmap.BLIT_SPAN_BASE);
    if (n == 0 or lo % 4 != 0 or !inAux(lo, lo + n * memmap.BLIT_SPAN_BYTES)) return;
    const list: [*]const u8 = @ptrFromInt(@as(usize, @intCast(lo)));
    for (0..@intCast(n)) |k| {
        const s = list + k * memmap.BLIT_SPAN_BYTES;
        const x0: i32 = @as(i16, @bitCast(rd16(s)));
        const x1: i32 = @as(i16, @bitCast(rd16(s + 2)));
        const y: i32 = @as(i16, @bitCast(rd16(s + 4)));
        if (y < c.y0 or y >= c.y1) continue;
        const du = rd32(s + 16);
        const dv = rd32(s + 20);
        var u = rd32(s + 8);
        var v = rd32(s + 12);
        const drow = @as(usize, @intCast(y)) * ds;
        var x = x0;
        while (x < x1) : (x += 1) {
            if (x >= c.x0 and x < c.x1) {
                if (t.put(d, drow + @as(usize, @intCast(x)), @truncate(u >> 16), @truncate(v >> 16))) cost.* += 1;
            }
            u +%= du;
            v +%= dv;
        }
    }
}

pub fn doMap(d: [*]u8, ds: u16, c: Clip, con: u8, con2: u8, cost: *u32) void {
    const t = Tex.load(con, con2) orelse return;
    const w = regs.r16(memmap.BLIT_W);
    const h = regs.r16(memmap.BLIT_H);
    const ms: u64 = regs.r16(memmap.BLIT_B_STRIDE);
    const lo: u64 = regs.r32(memmap.BLIT_B_BASE);
    if (w == 0 or h == 0 or lo % 2 != 0 or ms % 2 != 0) return;
    if (!inAux(lo, lo + (h - 1) * ms + 2 * @as(u64, w))) return;
    const map: [*]const u8 = @ptrFromInt(@as(usize, @intCast(lo)));
    const x0: i32 = regs.ri16(memmap.BLIT_X0);
    const y0: i32 = regs.ri16(memmap.BLIT_Y0);
    const uo = regs.r16(memmap.BLIT_U_OFF);
    const vo = regs.r16(memmap.BLIT_V_OFF);
    for (0..h) |j| {
        const py = y0 + @as(i32, @intCast(j));
        if (py < c.y0 or py >= c.y1) continue;
        const drow = @as(usize, @intCast(py)) * ds;
        for (0..w) |i| {
            const px = x0 + @as(i32, @intCast(i));
            if (px < c.x0 or px >= c.x1) continue;
            const e = rd16(map + j * ms + 2 * i);
            if (t.put(d, drow + @as(usize, @intCast(px)), (e & 0xFF) +% uo, (e >> 8) +% vo)) cost.* += 1;
        }
    }
}
