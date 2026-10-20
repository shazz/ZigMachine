// --------------------------------------------------------------------------
// When a linear copy may go to CHISEL with the bytes @memmove would write, and
// how it splits into rows (libs/zig/chisel_copy.zig is the driver). Pure
// arithmetic, so chisel_copy_test.zig checks it natively.
// --------------------------------------------------------------------------

/// The memory-map facts the decision needs (machine/sdk/memmap.zig).
pub const Map = struct {
    vram: usize, // OFF_VRAM: lowest region offset CHISEL writes
    region: usize, // REGION_BYTES
    cart: [2]usize, // the readable windows a SRC_ABS source must sit in (one of them)
    rom: [2]usize,
};

/// dst is inside the region at `base`, at or above OFF_VRAM; src inside one readable
/// window; no overlap (the row order would show); `len` at least `min`.
pub fn eligible(m: Map, base: usize, d0: usize, s0: usize, len: usize, min: usize) bool {
    if (len < min or len == 0 or base == 0) return false;
    if (d0 < base + m.vram or d0 + len > base + m.region) return false;
    if (s0 < d0 + len and d0 < s0 + len) return false;
    const wins = [_][2]usize{ m.cart, .{ base, base + m.region }, m.rom };
    for (wins) |w| if (s0 >= w[0] and s0 + len <= w[1]) return true;
    return false;
}

/// `len` bytes as `rows` rows of `w`, then a last row of `tail` bytes.
pub const Split = struct { rows: usize, tail: usize };
pub fn split(len: usize, w: usize) Split {
    return .{ .rows = len / w, .tail = len % w };
}
