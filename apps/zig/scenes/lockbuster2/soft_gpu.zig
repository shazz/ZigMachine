// --------------------------------------------------------------------------
// The chunky engine's backend in plain arrays: the CHISEL ops' meaning
// (machine/blitter.zig doBlit/doFill on a 320-stride plane) without the
// machine, for the native equivalence test. It also holds the board's rules
// as assertions: every rectangle is on its surface, and no copy reads the
// surface it writes (on the board that copy would run CHISEL's slow ordered
// mode). It counts the ops, for the blits-per-tick figure.
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: usize = 320;
pub const H: usize = 200;

pub const Soft = struct {
    surf: [3][W * H]u8 = undefined,
    ops: usize = 0,

    fn rect(x: u16, y: u16, w: u16, h: u16) void {
        std.debug.assert(w > 0 and h > 0 and @as(usize, x) + w <= W and @as(usize, y) + h <= H);
    }

    pub fn copy(self: *Soft, dst: u8, dx: u16, dy: u16, src: u8, sx: u16, sy: u16, w: u16, h: u16) void {
        std.debug.assert(dst != src);
        rect(dx, dy, w, h);
        rect(sx, sy, w, h);
        self.ops += 1;
        for (0..h) |j| {
            const d = (@as(usize, dy) + j) * W + dx;
            const s = (@as(usize, sy) + j) * W + sx;
            @memcpy(self.surf[dst][d .. d + w], self.surf[src][s .. s + w]);
        }
    }

    /// Rows dy and dy+1 of `dst` both take row sy of `src` (a source stride of 0).
    pub fn copyDouble(self: *Soft, dst: u8, dx: u16, dy: u16, src: u8, sx: u16, sy: u16, w: u16) void {
        std.debug.assert(dst != src);
        rect(dx, dy, w, 2);
        rect(sx, sy, w, 1);
        self.ops += 1;
        const s = @as(usize, sy) * W + sx;
        for (0..2) |j| {
            const d = (@as(usize, dy) + j) * W + dx;
            @memcpy(self.surf[dst][d .. d + w], self.surf[src][s .. s + w]);
        }
    }

    pub fn image(self: *Soft, dst: u8, dx: u16, dy: u16, pixels: []const u8, src_w: usize, sx: u16, sy: u16, w: u16, h: u16) void {
        rect(dx, dy, w, h);
        std.debug.assert(@as(usize, sx) + w <= src_w and (@as(usize, sy) + h) * src_w <= pixels.len);
        self.ops += 1;
        for (0..h) |j| {
            const d = (@as(usize, dy) + j) * W + dx;
            const s = (@as(usize, sy) + j) * src_w + sx;
            @memcpy(self.surf[dst][d .. d + w], pixels[s .. s + w]);
        }
    }

    pub fn fill(self: *Soft, dst: u8, x: u16, y: u16, w: u16, h: u16, v: u8) void {
        rect(x, y, w, h);
        self.ops += 1;
        for (0..h) |j| {
            const d = (@as(usize, y) + j) * W + x;
            @memset(self.surf[dst][d .. d + w], v);
        }
    }

    /// The CPU's part: one row's indices ANDed with `keep` (not a blit).
    pub fn andMask(self: *Soft, dst: u8, x: u16, y: u16, w: u16, keep: u8) void {
        rect(x, y, w, 1);
        const d = @as(usize, y) * W + x;
        for (self.surf[dst][d .. d + w]) |*p| p.* &= keep;
    }
};
