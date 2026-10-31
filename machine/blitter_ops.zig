// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter: the v1 ops. FILL, BLIT (3-source minterm /
// colour-key cookie-cut), LINE (Bresenham), TRIANGLE (deterministic odd-even
// scanline fill). Each writes the destination as chunky 8bpp palette indices
// and adds its cost to CYCLES. See docs/BLITTER_HW_SPEC.md §4.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const regs = @import("blitter_regs.zig");
const check = @import("blitter_check.zig");
const Clip = regs.Clip;
const r8 = regs.r8;
const r16 = regs.r16;
const ri16 = regs.ri16;
const r32 = regs.r32;

pub fn doFill(d: [*]u8, ds: u16, c: Clip, con2: u8, cost: *u32) void {
    const x0 = ri16(memmap.BLIT_X0);
    const y0 = ri16(memmap.BLIT_Y0);
    const w = r16(memmap.BLIT_W);
    const h = r16(memmap.BLIT_H);
    const fg = r8(memmap.BLIT_COLOR);
    const bg = r8(memmap.BLIT_BG_COLOR);
    const halftone = regs.haveHalftone(con2);
    // Combining with the destination is opt-in (CON2.FILL_MT): FILL ignored
    // MINTERM before 1.5.0, so a caller that never wrote the register would
    // otherwise start obeying whatever the previous op left there. MT_B is the
    // identity for D = LF(0, src, D), so the plain plot stays the fast path.
    const mt = r8(memmap.BLIT_MINTERM);
    const combine = con2 & memmap.CON2_FILL_MT != 0 and mt != memmap.MT_B;
    var j: u16 = 0;
    while (j < h) : (j += 1) {
        var i: u16 = 0;
        while (i < w) : (i += 1) {
            const px = @as(i32, x0) + i;
            const py = @as(i32, y0) + j;
            const v = if (halftone) (if (regs.halftoneBit(px, py)) fg else bg) else fg;
            if (combine) {
                if (regs.inClip(c, px, py)) {
                    const idx = @as(usize, @intCast(py)) * ds + @as(usize, @intCast(px));
                    d[idx] = regs.applyMinterm(0, v, d[idx], mt); // channel B = src, C = dest
                }
            } else {
                regs.plot(d, ds, c, px, py, v);
            }
            cost.* += 1;
        }
    }
}

pub fn doBlit(d: [*]u8, ds: u16, c: Clip, con: u8, cost: *u32) void {
    const s = BlitSetup.load(con) orelse return; // all registers read ONCE, not per pixel
    var jj: u16 = 0;
    while (jj < s.h) : (jj += 1) {
        const j: u16 = if (s.desc) s.h - 1 - jj else jj;
        const py = @as(i32, s.y0) + j;
        if (py < c.y0 or py >= c.y1) continue;
        const drow = @as(usize, @intCast(py)) * ds;
        const arow = @as(usize, j) * s.a_stride;
        const brow = @as(usize, j) * s.b_stride;
        var ii: u16 = 0;
        while (ii < s.w) : (ii += 1) {
            const i: u16 = if (s.desc) s.w - 1 - ii else ii;
            const px = @as(i32, s.x0) + i;
            if (px < c.x0 or px >= c.x1) continue;
            const b = if (s.use_b) s.b_src[brow + i] else 0;
            if (s.key_en and b == s.key) continue; // cookie-cut transparent pixel
            const di = drow + @as(usize, @intCast(px));
            if (s.plain) {
                d[di] = b; // fast path: D = B (plain / keyed copy)
            } else {
                const a = if (s.use_a) s.a_src[arow + i] else 0;
                const cc = if (s.use_c) d[di] else 0;
                d[di] = regs.applyMinterm(a, b, cc, s.mt);
            }
            cost.* += 1;
        }
    }
}

// One-time decode of the BLIT register block, so the inner loop touches only
// locals. `plain` is the D = B copy fast path (skips the per-bit minterm).
// Null when there is nothing to draw or an absolute source was refused.
const BlitSetup = struct {
    w: u16,
    h: u16,
    x0: i16,
    y0: i16,
    mt: u8,
    key: u8,
    key_en: bool,
    desc: bool,
    use_a: bool,
    use_b: bool,
    use_c: bool,
    plain: bool,
    a_src: [*]const u8,
    a_stride: usize,
    b_src: [*]const u8,
    b_stride: usize,

    fn load(con: u8) ?BlitSetup {
        const mt = r8(memmap.BLIT_MINTERM);
        const use_a = con & memmap.CON_USEA != 0;
        const use_b = con & memmap.CON_USEB != 0;
        const w = r16(memmap.BLIT_W);
        const h = r16(memmap.BLIT_H);
        if (w == 0 or h == 0) return null;
        const abs = r8(memmap.BLIT_CON2) & memmap.CON2_SRC_ABS != 0;
        const a_stride = r16(memmap.BLIT_A_STRIDE);
        const b_stride = r16(memmap.BLIT_B_STRIDE);
        // an unused channel is never read: point it at the region, unchecked
        const a_src = if (use_a) check.source(abs, r32(memmap.BLIT_A_BASE), a_stride, w, h) orelse return null else regs.region();
        const b_src = if (use_b) check.source(abs, r32(memmap.BLIT_B_BASE), b_stride, w, h) orelse return null else regs.region();
        return .{
            .w = w,
            .h = h,
            .x0 = ri16(memmap.BLIT_X0),
            .y0 = ri16(memmap.BLIT_Y0),
            .mt = mt,
            .key = r8(memmap.BLIT_COLOR_KEY),
            .key_en = con & memmap.CON_KEY_EN != 0,
            .desc = con & memmap.CON_DESC != 0,
            .use_a = use_a,
            .use_b = use_b,
            .use_c = con & memmap.CON_USEC != 0,
            .plain = mt == memmap.MT_B and use_b and !use_a,
            .a_src = a_src,
            .a_stride = a_stride,
            .b_src = b_src,
            .b_stride = b_stride,
        };
    }
};

// LINE — Bresenham, combining COLOR (channel B) with the destination (channel
// C) through MINTERM, so MT_B copies and MT_XOR_BC gives reversible wireframe.
pub fn doLine(d: [*]u8, ds: u16, c: Clip, cost: *u32) void {
    const mt = r8(memmap.BLIT_MINTERM);
    const color = r8(memmap.BLIT_COLOR);
    var x0: i32 = ri16(memmap.BLIT_X0);
    var y0: i32 = ri16(memmap.BLIT_Y0);
    const x1: i32 = ri16(memmap.BLIT_X1);
    const y1: i32 = ri16(memmap.BLIT_Y1);
    const dx: i32 = @intCast(@abs(x1 - x0));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    while (true) {
        linePixel(d, ds, c, mt, color, x0, y0);
        cost.* += 1;
        if (x0 == x1 and y0 == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

inline fn linePixel(d: [*]u8, ds: u16, c: Clip, mt: u8, color: u8, x: i32, y: i32) void {
    if (!regs.inClip(c, x, y)) return;
    const idx = @as(usize, @intCast(y)) * ds + @as(usize, @intCast(x));
    d[idx] = regs.applyMinterm(0, color, d[idx], mt);
}

// TRIANGLE — deterministic odd-even scanline fill (the sealed convenience over
// the Amiga edge+area-fill two-pass; exact and gap-free for a single triangle).
pub fn doTriangle(d: [*]u8, ds: u16, c: Clip, con2: u8, cost: *u32) void {
    const xs = [3]i32{ ri16(memmap.BLIT_X0), ri16(memmap.BLIT_X1), ri16(memmap.BLIT_X2) };
    const ys = [3]i32{ ri16(memmap.BLIT_Y0), ri16(memmap.BLIT_Y1), ri16(memmap.BLIT_Y2) };
    const color = r8(memmap.BLIT_COLOR);
    const bg = r8(memmap.BLIT_BG_COLOR);
    const mt = r8(memmap.BLIT_MINTERM); // combine fill with dest: MT_B copies, MT_OR_BC = glenz
    const halftone = regs.haveHalftone(con2); // dithered fill (COLOR / BG_COLOR) when a pattern is loaded
    var ymin = @min(ys[0], @min(ys[1], ys[2]));
    var ymax = @max(ys[0], @max(ys[1], ys[2]));
    ymin = @max(ymin, c.y0);
    ymax = @min(ymax, c.y1 - 1);
    var y = ymin;
    while (y <= ymax) : (y += 1) {
        var xl: i32 = std.math.maxInt(i32);
        var xr: i32 = std.math.minInt(i32);
        crossSpan(xs, ys, y, &xl, &xr);
        if (xr < xl) continue;
        var x = @max(xl, c.x0);
        const xend = @min(xr, c.x1 - 1);
        while (x <= xend) : (x += 1) {
            const idx = @as(usize, @intCast(y)) * ds + @as(usize, @intCast(x));
            const src = if (halftone) (if (regs.halftoneBit(x, y)) color else bg) else color;
            d[idx] = regs.applyMinterm(0, src, d[idx], mt); // channel B = src, C = dest
            cost.* += 1;
        }
    }
}

// Odd-even: for a scanline at pixel-centre y+0.5, find the min/max x where the
// triangle edges cross, using the top-left half-open rule [y0,y1) for stability.
fn crossSpan(xs: [3]i32, ys: [3]i32, y: i32, xl: *i32, xr: *i32) void {
    var e: usize = 0;
    while (e < 3) : (e += 1) {
        const a = e;
        const b = (e + 1) % 3;
        var ay = ys[a];
        var ax = xs[a];
        var by = ys[b];
        var bx = xs[b];
        if (ay == by) continue;
        if (ay > by) {
            std.mem.swap(i32, &ay, &by);
            std.mem.swap(i32, &ax, &bx);
        }
        if (y < ay or y >= by) continue; // half-open [ay, by)
        const x = ax + @divFloor((bx - ax) * (y - ay), (by - ay));
        xl.* = @min(xl.*, x);
        xr.* = @max(xr.*, x);
    }
}
