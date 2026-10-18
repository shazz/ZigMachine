// --------------------------------------------------------------------------
// Which CHISEL FILLs clear a plane exactly as @memset(fb[0 .. rows * stride])
// does. The driver is libs/zig/plane_clear.zig; this half is pure arithmetic so
// chisel_clear_test.zig can check it natively against the machine's clip rule.
//
// Why: on the board a memset is ~86 cycles a WORD (every store is a blocking
// DDR write), a CHISEL fill ~1.85 cycles a BYTE, so a 64000-byte clear drops
// from ~1.4 Mc to ~0.12 Mc.
//
// The machine clips a FILL to the destination (x < stride, y < the height its
// stride implies: 280 rows for the 400-wide fullscreen stride, else 200) and
// refuses one whose box leaves the video region; and the board's CHISEL takes
// only destinations at or above OFF_VRAM (it runs the machine's software fill on
// the CPU otherwise). So the clear is a run of full-stride fills of at most
// that many rows each, stacked down the buffer, or no fill at all.
// --------------------------------------------------------------------------

/// The memory-map facts the plan needs (machine/sdk/memmap.zig).
pub const Geometry = struct {
    vram: usize, // OFF_VRAM: lowest offset the board's CHISEL takes
    region: usize, // REGION_BYTES: a fill must end inside
    full_stride: u16, // STRIDE_FULLSCREEN
    full_h: u16, // PHYSICAL_HEIGHT
    normal_h: u16, // HEIGHT
};

/// The machine's dstHeight(stride): the rows a fill on this stride may reach.
pub fn rowsPerFill(g: Geometry, stride: u16) u16 {
    return if (stride == g.full_stride) g.full_h else g.normal_h;
}

/// True when the buffer at region offset `off`, `rows` x `stride`, can be
/// cleared by CHISEL fills (whole buffer inside [vram, region)).
pub fn usable(g: Geometry, off: usize, stride: u16, rows: u16) bool {
    if (stride == 0 or rows == 0) return false;
    const end: u64 = @as(u64, off) + @as(u64, rows) * stride;
    return off >= g.vram and end <= g.region;
}

/// One fill: `h` rows of `stride` at region offset `off`.
pub const Fill = struct { off: usize, h: u16 };

/// The i-th fill of the clear (null past the last one).
pub fn fillAt(g: Geometry, off: usize, stride: u16, rows: u16, i: usize) ?Fill {
    const per: usize = rowsPerFill(g, stride);
    const first = i * per;
    if (first >= rows) return null;
    return .{ .off = off + first * stride, .h = @intCast(@min(per, rows - first)) };
}
