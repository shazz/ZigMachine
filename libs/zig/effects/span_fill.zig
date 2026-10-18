// --------------------------------------------------------------------------
// @memset(out, v), storing only the words that change.
//
// On ZIGGY every store is a blocking DDR write (~86 cycles a word through a
// memset, board-calibrated) while a load hits the data cache. A span filler
// whose shapes barely move between frames (a polygon over its own previous
// frame, a band redrawn in place) rewrote mostly identical bytes: union_tnt3's
// faces stored 42 KB a frame of which 38 KB were already there. Reading first
// costs a load and a compare a word; the bytes left are the memset's exactly
// (span_fill_test.zig compares the two on every alignment and length).
//
// Word accesses only at 4-aligned addresses (the board traps a misaligned
// word); the unaligned head and tail go a byte at a time, compared the same way.
// --------------------------------------------------------------------------

pub fn fill(out: []u8, v: u8) void {
    var i: usize = 0;
    const n = out.len;
    const head = @min(n, (4 -% @intFromPtr(out.ptr)) & 3);
    while (i < head) : (i += 1) if (out[i] != v) {
        out[i] = v;
    };
    const pat: u32 = @as(u32, v) * 0x0101_0101;
    while (i + 4 <= n) : (i += 4) {
        const wp: *u32 = @ptrCast(@alignCast(out.ptr + i));
        if (wp.* != pat) wp.* = pat;
    }
    while (i < n) : (i += 1) if (out[i] != v) {
        out[i] = v;
    };
}
