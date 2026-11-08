// --------------------------------------------------------------------------
// The frame's runs (vic_runs.zig) onto the plane, sprite 7's first: each a rectangle of an
// expanded block (vic_cache.zig), cut to the columns the line's borders let through and split
// at the PAL wrap (a sprite whose X passes $1F7 goes on at X 0).
// Big rectangles go to CHISEL (a keyed blit from cart RAM: the source is never the plane, so
// no in-plane copy), small ones are a keyed CPU copy: a CHISEL op costs ~800-1,100 cycles
// before its first pixel and a keyed CPU copy ~10 a pixel, so below MIN_BLIT the CPU is cheaper.
// The ZIG mode (zig_mode.zig) paints the same runs moved by a few pixels: `dr`, `dc`.
// --------------------------------------------------------------------------
const draw = @import("vic_draw.zig");
const cache = @import("vic_cache.zig");
const runs_mod = @import("vic_runs.zig");
const px = @import("vic_pixels.zig");

const COLS = px.COLS;
const ROWS = draw.ROWS;
const PAL_X = 504;
pub const MIN_BLIT = 128; // pixels: ~10 cycles a pixel on the CPU against ~1,000 + 1 on CHISEL

/// CHISEL's keyed copy of a w x h box of `src` (rows `src_w` apart, from column sx, row sy)
/// to the plane at (x, y); 0 is the key.
pub const Blit = struct {
    ctx: *anyopaque,
    f: *const fn (ctx: *anyopaque, x: u16, y: u16, src: []const u8, src_w: u16, sx: u16, sy: u16, w: u16, h: u16) void,
};

/// The columns [lo, hi) of each row that hold sprite pixels: what the next frame erases.
pub const Spans = struct {
    lo: [ROWS]u16 = .{COLS} ** ROWS,
    hi: [ROWS]u16 = .{0} ** ROWS,

    pub fn erase(self: *Spans, pix: *[ROWS * COLS]u8) void {
        for (0..ROWS) |r| {
            if (self.lo[r] >= self.hi[r]) continue;
            @memset(pix[r * COLS ..][self.lo[r]..self.hi[r]], 0);
            self.lo[r] = COLS;
            self.hi[r] = 0;
        }
    }
};

/// Where runs are painted: the plane, its spans, the expanded blocks and CHISEL.
pub const Pen = struct {
    pix: *[ROWS * COLS]u8,
    spans: *Spans,
    cache: ?*cache.Cache, // null: each run expands its block on the stack (tests)
    blit: ?Blit, // null: every run is a CPU copy
    mem: draw.Mem,
};

/// Draw every run where it is, sprite 7's first; returns the CHISEL ops it took.
pub fn all(pen: Pen, runs: []const runs_mod.Run) u32 {
    var ops: u32 = 0;
    var s: u8 = 8;
    while (s > 0) {
        s -= 1;
        for (runs) |*run| {
            if (run.s == s) ops += one(pen, run, 0, 0);
        }
    }
    return ops;
}

/// One run, `dr` rows down and `dc` columns right of where it is.
pub fn one(pen: Pen, run: *const runs_mod.Run, dr: i32, dc: i32) u32 {
    const slot = cache.slot(run.bit(25), run.block()) orelse return 0; // reads as 0: nothing
    const look = run.look();
    var local: [cache.IMAGE]u8 = undefined;
    const img: []const u8 = if (pen.cache) |c| c.image(slot, look, pen.mem.block(slot)) else blk: {
        cache.expand(&local, look, pen.mem.block(slot));
        break :blk local[0 .. cache.ROWS * @as(usize, look.width())];
    };
    // the rows that land on the plane
    const top = @as(i32, run.r0) + dr;
    const r0: u16 = @intCast(@max(top, 0));
    const r1: u16 = @intCast(@min(top + run.n, ROWS));
    if (r0 >= r1) return 0;
    const sy: u16 = run.row0() + @as(u16, @intCast(@as(i32, r0) - top));
    const w: u16 = look.width();
    const left: u16 = if (run.bit(23)) 0 else 40; // X < 24: the left border
    const right: u16 = if (run.bit(24)) COLS else 360; // X >= 344: the right border
    const c: u16 = @intCast(@mod(@as(i32, run.col()) + dc, PAL_X));
    const box = Box{ .img = img, .w = w, .sy = sy, .r0 = r0, .n = r1 - r0, .left = left, .right = right };
    // the part before the PAL wrap, then the part after it (columns 0.. again)
    var ops = piece(pen, box, c, @min(c + w, PAL_X), 0);
    if (c + w > PAL_X) ops += piece(pen, box, 0, c + w - PAL_X, PAL_X - c);
    return ops;
}

const Box = struct { img: []const u8, w: u16, sy: u16, r0: u16, n: u16, left: u16, right: u16 };

// Columns [a, b) of the box, whose source starts at image column `so`, cut to [left, right).
fn piece(pen: Pen, box: Box, a: u16, b: u16, so: u16) u32 {
    const x0 = @max(a, box.left);
    const x1 = @min(b, box.right);
    if (x0 >= x1) return 0;
    const sx = so + (x0 - a);
    const cw = x1 - x0;
    for (box.r0..box.r0 + box.n) |r| {
        pen.spans.lo[r] = @min(pen.spans.lo[r], x0);
        pen.spans.hi[r] = @max(pen.spans.hi[r], x1);
    }
    if (pen.blit) |bl| {
        if (@as(u32, cw) * box.n >= MIN_BLIT) {
            bl.f(bl.ctx, x0, box.r0, box.img, box.w, sx, box.sy, cw, box.n);
            return 1;
        }
    }
    for (0..box.n) |i| {
        const src = box.img[(box.sy + i) * box.w + sx ..];
        px.keyed(pen.pix[(box.r0 + i) * COLS + x0 ..].ptr, src.ptr, cw);
    }
    return 0;
}
