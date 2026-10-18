// --------------------------------------------------------------------------
// Where a row's pixels CHANGE, as bit masks, so the compositor looks at the few
// pixels that start a new run instead of every pixel (the oldskool rule: only
// touch what changes). back.png and overlay.png are static: their per-image-row
// "differs from the pixel on its left" masks are built once at start; a screen
// row ORs the masks of the (up to six) image rows it is made of, plus the edges
// of the letter ink, and only the set bits cost a colour lookup. The result is
// the same run structure the per-pixel loop found (its key was injective over
// exactly these sources), so the palette entries are handed out in the same order.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const WORDS = A.W / 32;
pub const Mask = [WORDS]u32;

pub const Edges = struct {
    back: [A.H]Mask,
    overlay: [A.H]Mask,

    pub fn build(self: *Edges, img: *const A.Images) void {
        for (0..A.H) |y| {
            rowEdges(&self.back[y], img.back[y * A.W ..][0..A.W]);
            rowEdges(&self.overlay[y], img.overlay[y * A.W ..][0..A.W]);
        }
    }
};

fn rowEdges(m: *Mask, px: *const [A.W]u8) void {
    m.* = [_]u32{0} ** WORDS;
    for (1..A.W) |x| {
        if (px[x] != px[x - 1]) m[x >> 5] |= @as(u32, 1) << @intCast(x & 31);
    }
}

pub fn orInto(dst: *Mask, src: *const Mask) void {
    for (dst, src) |*d, s| d.* |= s;
}

/// Set bits x0..x1 (exclusive) of `m`.
pub fn setRange(m: *Mask, x0: usize, x1: usize) void {
    var x = x0;
    while (x < x1) {
        const w = x >> 5;
        const lo: u5 = @intCast(x & 31);
        const n = @min(x1 - x, 32 - @as(usize, lo));
        const bits: u32 = if (n == 32) ~@as(u32, 0) else ((@as(u32, 1) << @intCast(n)) - 1);
        m[w] |= bits << lo;
        x += n;
    }
}

/// OR into `dst` the pixels where `ink` differs from the pixel on its left.
pub fn orInkEdges(dst: *Mask, ink: *const Mask) void {
    var carry: u32 = 0; // bit 31 of the previous word: the pixel left of bit 0
    for (dst, ink) |*d, w| {
        d.* |= w ^ ((w << 1) | carry);
        carry = w >> 31;
    }
}

pub inline fn bit(m: *const Mask, x: usize) bool {
    return (m[x >> 5] >> @intCast(x & 31)) & 1 != 0;
}
