// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter (the 2D drawing coprocessor).
//
// Lives inside machine-video.wasm, sharing the video hardware region with the
// framebuffers it draws into. ZigOS sets the blitter register block (memmap
// BLIT_*) then calls the sealed `hwBlit()` export, which runs execute() here.
//
// v1 is synchronous: FILL, BLIT (3-source minterm / colour-key cookie-cut),
// LINE (Bresenham), TRIANGLE (deterministic odd-even scanline fill). It writes
// the logical framebuffers as chunky 8bpp palette indices; the video machine
// composites them as usual. Area-fill (CON.IFE/EFE) is reserved for v2.
//
// Coders never see this source. See docs/BLITTER_HW_SPEC.md for the model.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("sdk/memmap.zig");

inline fn region() [*]u8 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE);
}
inline fn r8(off: usize) u8 {
    return region()[off];
}
inline fn w8(off: usize, v: u8) void {
    region()[off] = v;
}
inline fn r16(off: usize) u16 {
    return std.mem.readInt(u16, region()[off .. off + 2][0..2], .little);
}
inline fn ri16(off: usize) i16 {
    return std.mem.readInt(i16, region()[off .. off + 2][0..2], .little);
}
inline fn r32(off: usize) u32 {
    return std.mem.readInt(u32, region()[off .. off + 4][0..4], .little);
}
inline fn w32(off: usize, v: u32) void {
    std.mem.writeInt(u32, region()[off .. off + 4][0..4], v, .little);
}

// Destination plane height is implied by its stride (same rule the video
// machine uses to size a plane), so a blit can never spill into a neighbour's
// VRAM slot when the clip rect is left disabled.
inline fn dstHeight(stride: u16) u16 {
    return if (stride == memmap.STRIDE_FULLSCREEN) memmap.PHYSICAL_HEIGHT else memmap.HEIGHT;
}

const Clip = struct {
    x0: i32,
    y0: i32,
    x1: i32, // exclusive
    y1: i32, // exclusive
};

// The effective clip: the destination-buffer bounds, further restricted by the
// CLIP rect when CON.CLIP_EN is set.
fn clipRect(con: u8, d_stride: u16) Clip {
    var c = Clip{ .x0 = 0, .y0 = 0, .x1 = d_stride, .y1 = dstHeight(d_stride) };
    if (con & memmap.CON_CLIP_EN != 0) {
        const cx: i32 = r16(memmap.BLIT_CLIP_X);
        const cy: i32 = r16(memmap.BLIT_CLIP_Y);
        c.x0 = @max(c.x0, cx);
        c.y0 = @max(c.y0, cy);
        c.x1 = @min(c.x1, cx + r16(memmap.BLIT_CLIP_W));
        c.y1 = @min(c.y1, cy + r16(memmap.BLIT_CLIP_H));
    }
    return c;
}

inline fn inClip(c: Clip, x: i32, y: i32) bool {
    return x >= c.x0 and x < c.x1 and y >= c.y0 and y < c.y1;
}

inline fn plot(d: [*]u8, stride: u16, c: Clip, x: i32, y: i32, v: u8) void {
    if (inClip(c, x, y)) d[@as(usize, @intCast(y)) * stride + @as(usize, @intCast(x))] = v;
}

// D = LF(A,B,C): the 8-bit minterm is a truth table indexed by (a<<2|b<<1|c),
// applied independently to each of the 8 bits of the chunky palette index.
fn applyMinterm(a: u8, b: u8, c: u8, mt: u8) u8 {
    var out: u8 = 0;
    var bit: u3 = 0;
    while (true) : (bit += 1) {
        const idx: u3 = @intCast((((a >> bit) & 1) << 2) | (((b >> bit) & 1) << 1) | ((c >> bit) & 1));
        out |= @as(u8, (mt >> idx) & 1) << bit;
        if (bit == 7) break;
    }
    return out;
}

// --------------------------------------------------------------------------
// Ops
// --------------------------------------------------------------------------
fn doFill(d: [*]u8, ds: u16, c: Clip, cost: *u32) void {
    const x0 = ri16(memmap.BLIT_X0);
    const y0 = ri16(memmap.BLIT_Y0);
    const w = r16(memmap.BLIT_W);
    const h = r16(memmap.BLIT_H);
    const fg = r8(memmap.BLIT_COLOR);
    const bg = r8(memmap.BLIT_BG_COLOR);
    const halftone = haveHalftone();
    var j: u16 = 0;
    while (j < h) : (j += 1) {
        var i: u16 = 0;
        while (i < w) : (i += 1) {
            const px = @as(i32, x0) + i;
            const py = @as(i32, y0) + j;
            const v = if (halftone) (if (halftoneBit(px, py)) fg else bg) else fg;
            plot(d, ds, c, px, py, v);
            cost.* += 1;
        }
    }
}

fn doBlit(d: [*]u8, ds: u16, c: Clip, con: u8, cost: *u32) void {
    const s = BlitSetup.load(con); // all registers read ONCE, not per pixel
    const mem = region();
    var jj: u16 = 0;
    while (jj < s.h) : (jj += 1) {
        const j: u16 = if (s.desc) s.h - 1 - jj else jj;
        const py = @as(i32, s.y0) + j;
        if (py < c.y0 or py >= c.y1) continue;
        const drow = @as(usize, @intCast(py)) * ds;
        const arow = s.a_base + @as(usize, j) * s.a_stride;
        const brow = s.b_base + @as(usize, j) * s.b_stride;
        var ii: u16 = 0;
        while (ii < s.w) : (ii += 1) {
            const i: u16 = if (s.desc) s.w - 1 - ii else ii;
            const px = @as(i32, s.x0) + i;
            if (px < c.x0 or px >= c.x1) continue;
            const b = if (s.use_b) mem[brow + i] else 0;
            if (s.key_en and b == s.key) continue; // cookie-cut transparent pixel
            const di = drow + @as(usize, @intCast(px));
            if (s.plain) {
                d[di] = b; // fast path: D = B (plain / keyed copy)
            } else {
                const a = if (s.use_a) mem[arow + i] else 0;
                const cc = if (s.use_c) d[di] else 0;
                d[di] = applyMinterm(a, b, cc, s.mt);
            }
            cost.* += 1;
        }
    }
}

// One-time decode of the BLIT register block, so the inner loop touches only
// locals. `plain` is the D = B copy fast path (skips the per-bit minterm).
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
    a_base: usize,
    a_stride: usize,
    b_base: usize,
    b_stride: usize,

    fn load(con: u8) BlitSetup {
        const mt = r8(memmap.BLIT_MINTERM);
        const use_a = con & memmap.CON_USEA != 0;
        const use_b = con & memmap.CON_USEB != 0;
        return .{
            .w = r16(memmap.BLIT_W),
            .h = r16(memmap.BLIT_H),
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
            .a_base = r32(memmap.BLIT_A_BASE),
            .a_stride = r16(memmap.BLIT_A_STRIDE),
            .b_base = r32(memmap.BLIT_B_BASE),
            .b_stride = r16(memmap.BLIT_B_STRIDE),
        };
    }
};

// LINE — Bresenham, combining COLOR (channel B) with the destination (channel
// C) through MINTERM, so MT_B copies and MT_XOR_BC gives reversible wireframe.
fn doLine(d: [*]u8, ds: u16, c: Clip, cost: *u32) void {
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
    if (!inClip(c, x, y)) return;
    const idx = @as(usize, @intCast(y)) * ds + @as(usize, @intCast(x));
    d[idx] = applyMinterm(0, color, d[idx], mt);
}

// TRIANGLE — deterministic odd-even scanline fill (the sealed convenience over
// the Amiga edge+area-fill two-pass; exact and gap-free for a single triangle).
fn doTriangle(d: [*]u8, ds: u16, c: Clip, cost: *u32) void {
    const xs = [3]i32{ ri16(memmap.BLIT_X0), ri16(memmap.BLIT_X1), ri16(memmap.BLIT_X2) };
    const ys = [3]i32{ ri16(memmap.BLIT_Y0), ri16(memmap.BLIT_Y1), ri16(memmap.BLIT_Y2) };
    const color = r8(memmap.BLIT_COLOR);
    const bg = r8(memmap.BLIT_BG_COLOR);
    const mt = r8(memmap.BLIT_MINTERM); // combine fill with dest: MT_B copies, MT_OR_BC = glenz
    const halftone = haveHalftone(); // dithered fill (COLOR / BG_COLOR) when a pattern is loaded
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
            const src = if (halftone) (if (halftoneBit(x, y)) color else bg) else color;
            d[idx] = applyMinterm(0, src, d[idx], mt); // channel B = src, C = dest
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

// --------------------------------------------------------------------------
// Halftone (16x16 1-bit pattern selecting COLOR / BG_COLOR)
// --------------------------------------------------------------------------
fn haveHalftone() bool {
    var i: usize = 0;
    while (i < 16) : (i += 1) if (r16(memmap.BLIT_HALFTONE + i * 2) != 0) return true;
    return false;
}

inline fn halftoneBit(x: i32, y: i32) bool {
    const row = r16(memmap.BLIT_HALFTONE + @as(usize, @intCast(@mod(y, 16))) * 2);
    return (row >> @as(u4, @intCast(@mod(x, 16)))) & 1 != 0;
}

// --------------------------------------------------------------------------
// Entry point (wrapped as hwBlit() in machine_video.zig)
// --------------------------------------------------------------------------
pub fn execute() void {
    const cmd = r8(memmap.BLIT_COMMAND);
    if (cmd == memmap.BLIT_CMD_NOP) return;
    w8(memmap.BLIT_STATUS, memmap.BLIT_STATUS_BUSY);

    const con = r8(memmap.BLIT_CON);
    const d_base: usize = r32(memmap.BLIT_D_BASE);
    const d_stride = r16(memmap.BLIT_D_STRIDE);
    const d: [*]u8 = @ptrFromInt(memmap.HW_VIDEO_BASE + d_base);
    const clip = clipRect(con, d_stride);
    var cost: u32 = 0;

    switch (cmd) {
        memmap.BLIT_CMD_FILL => doFill(d, d_stride, clip, &cost),
        memmap.BLIT_CMD_BLIT => doBlit(d, d_stride, clip, con, &cost),
        memmap.BLIT_CMD_LINE => doLine(d, d_stride, clip, &cost),
        memmap.BLIT_CMD_TRIANGLE => doTriangle(d, d_stride, clip, &cost),
        else => {},
    }

    w32(memmap.BLIT_CYCLES, cost);
    w8(memmap.BLIT_STATUS, 0);
}
