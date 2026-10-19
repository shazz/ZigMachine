// --------------------------------------------------------------------------
// The frame's CHISEL work outside the scroller: clears, the VU bars, the ULM
// logo's rows, the motif's strips and the potiches put back over all of them.
// Each was a CPU loop storing one pixel (or one word) at a time; on the board
// every such store is a blocking DDR write, where CHISEL fills ~2 cycles a
// byte and copies ~1 a pixel (blitImage reads the art straight from cart RAM).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const MOCHE_W = 236; // motifMoche: 32 strips of 2 rows at (140, 466), 472 wide
pub const MOCHE_LINES = 32;
const MOTIF = 12; // the 24x24 tile, halved
const REP_W = MOCHE_W + MOTIF - 1;

/// The 384x270 canvas at (x, y) of the plane: what the CODEF canvas draws
/// into, clipped as the canvas clips.
pub const Canvas = struct {
    fb: *zg.LogicalFB,
    bl: *zg.Blitter,
    x: i16,
    y: i16,
    w: i32,
    h: i32,

    /// fillRect, clipped to the canvas.
    pub fn fill(c: Canvas, x: i32, y: i32, w: usize, h: usize, v: u8) void {
        const x0 = @max(x, 0);
        const y0 = @max(y, 0);
        const x1 = @min(x + @as(i32, @intCast(w)), c.w);
        const y1 = @min(y + @as(i32, @intCast(h)), c.h);
        if (x0 >= x1 or y0 >= y1) return;
        c.bl.fill(c.fb, c.x + @as(i16, @intCast(x0)), c.y + @as(i16, @intCast(y0)), @intCast(x1 - x0), @intCast(y1 - y0), v);
    }

    /// `img` at (px, py), index 0 transparent, drawn only inside the rectangle
    /// (rx, ry, rw, rh) of the canvas.
    pub fn imageIn(c: Canvas, img: blit.Image, px: i32, py: i32, rx: i32, ry: i32, rw: usize, rh: usize) void {
        const x0 = @max(@max(px, rx), 0);
        const y0 = @max(@max(py, ry), 0);
        const x1 = @min(@min(px + @as(i32, @intCast(img.w)), rx + @as(i32, @intCast(rw))), c.w);
        const y1 = @min(@min(py + @as(i32, @intCast(img.h)), ry + @as(i32, @intCast(rh))), c.h);
        if (x0 >= x1 or y0 >= y1) return;
        c.bl.blitImage(c.fb, c.x + @as(i16, @intCast(x0)), c.y + @as(i16, @intCast(y0)), img.data, @intCast(img.w), //
            @intCast(x0 - px), @intCast(y0 - py), @intCast(x1 - x0), @intCast(y1 - y0), 0);
    }
};

/// fillRect(x, 180, 192, -level) on the meter canvas: a bar grows up from its
/// row 179, so the lit rows are k with 2k >= 180 - level, one fill a bar. Every
/// lit line is VU_INK; the copper colours it.
pub fn vu(c: Canvas, levels: [3]i32, xs: [3]i32, w: usize, top: usize, rows: usize) void {
    for (levels, xs) |level, x| {
        const k0: usize = @intCast(@max(@divFloor(180 - level + 1, 2), 0));
        if (k0 < rows) c.fill(x, @intCast(top + k0), w, rows - k0, A.VU_INK);
    }
}

/// Canvas row 140 + r shows logo row r at x = ulmDistTable[ulmCtr + r]:
/// halved, logo column (2X - x) >> 1 = X - ceil(x / 2). Index 0 is clear.
pub fn ulm(c: Canvas, drawn: usize, top: usize, bottom: usize) void {
    for (top..bottom + 1) |Y| {
        const r = 2 * Y - 140;
        const x = A.ulmDist(drawn + r);
        c.imageIn(A.ulm, @divFloor(x + 1, 2), @as(i32, @intCast(Y)) - @as(i32, @intCast(r >> 1)), 0, @intCast(Y), @intCast(c.w), 1);
    }
}

/// Each motif row repeated across the strip and then some: strip k is a
/// MOCHE_W window of row ((v % 24) >> 1) starting at column (shift >> 1) % 12,
/// since ((2i + shift) % 24) >> 1 = (i + (shift >> 1)) % 12.
var rep: *[MOTIF * REP_W]u8 = undefined;

pub fn initMoche() void {
    rep = zg.mem.mustAlloc(u8, MOTIF * REP_W)[0 .. MOTIF * REP_W];
    for (0..MOTIF) |r| {
        for (0..REP_W) |j| rep[r * REP_W + j] = A.moche.data[r * A.moche.w + j % MOTIF];
    }
}

/// Strip k (ST line y0 + k) samples the pattern at source row
/// floor(y + 2k + 0.5) and column 2X - 140 + round(mocheDist[ctr - k]).
pub fn moche(c: Canvas, drawn: usize, y: f64, x0: i32, y0: i32) void {
    comptime std.debug.assert(A.moche.w == MOTIF and A.moche.h == MOTIF);
    for (0..MOCHE_LINES) |k| {
        const ky = y0 + @as(i32, @intCast(k));
        // mocheDistCtr reaches mocheDist.length - 32 (the wrap test is >), so
        // strip 0 reads one past the table once a lap: undefined in the JS,
        // and drawImage given NaN draws nothing. Leave it black the same way.
        const at = drawn + MOCHE_LINES - k;
        if (at >= A.moche_dist.len) {
            c.fill(x0, ky, MOCHE_W, 1, 0);
            continue;
        }
        const fk: f64 = @floatFromInt(2 * k);
        const v: usize = @intFromFloat(@floor(y + fk + 0.5));
        const row = (v % 24) >> 1;
        const col = (@as(usize, A.moche_dist[at]) >> 1) % MOTIF;
        c.bl.blitImage(c.fb, c.x + @as(i16, @intCast(x0)), c.y + @as(i16, @intCast(ky)), rep, REP_W, //
            @intCast(col), @intCast(row), MOCHE_W, 1, null);
    }
}
