// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter: what execute() checks before it draws. Where a
// source may be read from (one readable window), and whether an op's clipped
// box stays inside the video region. See docs/BLITTER_HW_SPEC.md §2.
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");
const regs = @import("blitter_regs.zig");
const Clip = regs.Clip;

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
pub fn readable(base: u32, stride: u16, w: u16, h: u16) bool {
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
pub fn source(abs: bool, base: u32, stride: u16, w: u16, h: u16) ?[*]const u8 {
    if (!abs) {
        const end: u64 = @as(u64, base) + @as(u64, h - 1) * stride + w; // one past the last byte read
        return if (end <= memmap.REGION_BYTES) regs.region() + base else null;
    }
    if (!readable(base, stride, w, h)) return null;
    return @ptrFromInt(base);
}

// Would an op touching the clipped box [x0,x1) x [y0,y1) of D write inside the
// video region? The box is what the op can actually reach, not the plane size a
// stride implies: a packed tile ring views a plane with a 62400-byte stride and
// only ever writes its first rows. An empty box writes nothing and is fine.
pub fn destInRegion(d_base: u32, stride: u16, x0: i32, y0: i32, x1: i32, y1: i32) bool {
    if (x1 <= x0 or y1 <= y0) return true;
    const last: u64 = @as(u64, @intCast(y1 - 1)) * stride + @as(u64, @intCast(x1));
    return @as(u64, d_base) + last <= memmap.REGION_BYTES;
}

// The clipped bounding box an op can write, for destInRegion().
pub fn opBox(cmd: u8, c: Clip) Clip {
    var b = c;
    switch (cmd) {
        memmap.BLIT_CMD_FILL, memmap.BLIT_CMD_BLIT => {
            const x0: i32 = regs.ri16(memmap.BLIT_X0);
            const y0: i32 = regs.ri16(memmap.BLIT_Y0);
            b = .{ .x0 = x0, .y0 = y0, .x1 = x0 + regs.r16(memmap.BLIT_W), .y1 = y0 + regs.r16(memmap.BLIT_H) };
        },
        memmap.BLIT_CMD_LINE, memmap.BLIT_CMD_TRIANGLE => {
            const n: usize = if (cmd == memmap.BLIT_CMD_LINE) 2 else 3;
            const xs = [3]i32{ regs.ri16(memmap.BLIT_X0), regs.ri16(memmap.BLIT_X1), regs.ri16(memmap.BLIT_X2) };
            const ys = [3]i32{ regs.ri16(memmap.BLIT_Y0), regs.ri16(memmap.BLIT_Y1), regs.ri16(memmap.BLIT_Y2) };
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
