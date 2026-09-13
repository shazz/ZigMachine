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
                d[di] = applyMinterm(a, b, cc, s.mt);
            }
            cost.* += 1;
        }
    }
}

// Windows a SRC_ABS source may read, as [lo, hi) linear addresses. Everything a
// program may legitimately hold pixels in; never the machine's or audio's own RAM
// below the cart window, and never the gap between the video region and the ROM.
const Window = struct { lo: u64, hi: u64 };
const READABLE = [_]Window{
    .{ .lo = memmap.CART_RAM_BASE, .hi = memmap.CART_RAM_TOP },
    .{ .lo = memmap.HW_VIDEO_BASE, .hi = memmap.HW_VIDEO_BASE + memmap.REGION_BYTES },
    .{ .lo = memmap.ROM_RAM_BASE, .hi = memmap.ROM_RAM_TOP },
};

// Does the w x h rectangle read at base + j*stride + i lie inside ONE window?
// u64 so a huge stride x height cannot wrap back into range.
fn readable(base: u32, stride: u16, w: u16, h: u16) bool {
    const lo: u64 = base;
    const hi: u64 = lo + @as(u64, h - 1) * stride + w; // one past the last byte read
    for (READABLE) |win| {
        if (lo >= win.lo and hi <= win.hi) return true;
    }
    return false;
}

// A channel's pixel 0, or null when its rectangle is out of bounds. Relative: an
// offset whose rectangle must stay inside the video region (before 1.4.0 it was
// unchecked, and a bad BASE read past the end of memory and trapped the whole
// machine). Absolute (CON2.SRC_ABS): the address itself, inside one READABLE window.
fn source(abs: bool, base: u32, stride: u16, w: u16, h: u16) ?[*]const u8 {
    if (!abs) {
        const end: u64 = @as(u64, base) + @as(u64, h - 1) * stride + w; // one past the last byte read
        return if (end <= memmap.REGION_BYTES) region() + base else null;
    }
    if (!readable(base, stride, w, h)) return null;
    return @ptrFromInt(base);
}

// Would an op touching the clipped box [x0,x1) x [y0,y1) of D write inside the
// video region? The box is what the op can actually reach, not the plane size a
// stride implies: a packed tile ring views a plane with a 62400-byte stride and
// only ever writes its first rows. An empty box writes nothing and is fine.
fn destInRegion(d_base: u32, stride: u16, x0: i32, y0: i32, x1: i32, y1: i32) bool {
    if (x1 <= x0 or y1 <= y0) return true;
    const last: u64 = @as(u64, @intCast(y1 - 1)) * stride + @as(u64, @intCast(x1));
    return @as(u64, d_base) + last <= memmap.REGION_BYTES;
}

// The clipped bounding box an op can write, for destInRegion().
fn opBox(cmd: u8, c: Clip) Clip {
    var b = c;
    switch (cmd) {
        memmap.BLIT_CMD_FILL, memmap.BLIT_CMD_BLIT => {
            const x0: i32 = ri16(memmap.BLIT_X0);
            const y0: i32 = ri16(memmap.BLIT_Y0);
            b = .{ .x0 = x0, .y0 = y0, .x1 = x0 + r16(memmap.BLIT_W), .y1 = y0 + r16(memmap.BLIT_H) };
        },
        memmap.BLIT_CMD_LINE, memmap.BLIT_CMD_TRIANGLE => {
            const n: usize = if (cmd == memmap.BLIT_CMD_LINE) 2 else 3;
            const xs = [3]i32{ ri16(memmap.BLIT_X0), ri16(memmap.BLIT_X1), ri16(memmap.BLIT_X2) };
            const ys = [3]i32{ ri16(memmap.BLIT_Y0), ri16(memmap.BLIT_Y1), ri16(memmap.BLIT_Y2) };
            b = .{ .x0 = xs[0], .y0 = ys[0], .x1 = xs[0] + 1, .y1 = ys[0] + 1 };
            for (1..n) |k| {
                b.x0 = @min(b.x0, xs[k]);
                b.y0 = @min(b.y0, ys[k]);
                b.x1 = @max(b.x1, xs[k] + 1);
                b.y1 = @max(b.y1, ys[k] + 1);
            }
        },
        else => {},
    }
    return .{ .x0 = @max(b.x0, c.x0), .y0 = @max(b.y0, c.y0), .x1 = @min(b.x1, c.x1), .y1 = @min(b.y1, c.y1) };
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
        const a_src = if (use_a) source(abs, r32(memmap.BLIT_A_BASE), a_stride, w, h) orelse return null else region();
        const b_src = if (use_b) source(abs, r32(memmap.BLIT_B_BASE), b_stride, w, h) orelse return null else region();
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
    const clip = clipRect(con, d_stride);
    var cost: u32 = 0;

    // D never leaves the video region: before 1.4.0 a bad D_BASE could scribble
    // the ROM's RAM (it sits 2 MiB above the base) or trap past the end of memory.
    const box = opBox(cmd, clip);
    if (!destInRegion(r32(memmap.BLIT_D_BASE), d_stride, box.x0, box.y0, box.x1, box.y1)) {
        w32(memmap.BLIT_CYCLES, 0);
        w8(memmap.BLIT_STATUS, 0);
        return;
    }
    const d: [*]u8 = @ptrFromInt(memmap.HW_VIDEO_BASE + d_base);

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
