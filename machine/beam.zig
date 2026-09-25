// --------------------------------------------------------------------------
// BEAM (HW 1.6.0) — one physical line painted from mid-line colour-0 writes.
//
// On an ST a zero-bitplane screen is nothing but $FF8240 rewritten while the
// beam crosses the line: every move.w changes the colour from that cycle on,
// and the last value stays in the register into the next line. This file is the
// pure half of that: validate a line's write list against the 68000's limits
// and paint the spans. video.zig feeds it the register block; beam_test.zig
// feeds it arrays, so the rules are proven natively.
//
// The limits, all in low-res pixels (one pixel per 8 MHz cycle here):
//   - x snaps DOWN to BEAM_GRID (4): the 68000 reaches the bus in 4-cycle slots;
//   - an accepted write is at least BEAM_MIN_GAP (8) px after the previous one,
//     which also makes x strictly increasing: move.w Dn,(An) is 8 cycles;
//   - at most BEAM_MAX (64) writes a line, and x < PHYSICAL_WIDTH.
// A write that breaks one is DROPPED and counted, never absorbed.
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");

pub const W: usize = memmap.PHYSICAL_WIDTH; // 400 px, left border at 0

pub const Line = struct {
    bg: u32, // the colour the line ENDS on: the register's value for the next line
    dropped: u32, // writes this line rejected
};

/// An ST or STE colour word ($0RGB) as the RGBA the palettes hold. Each STE
/// nibble is 3 bits + its LSB in bit 3; the 4-bit level times 16 puts every
/// plain ST colour (bit 3 clear) on the nibble*32 grid (0..224) that ST-ripped
/// palettes use, and an STE half-step 16 above it. Bits 12..15 are ignored.
pub fn stToRgba(word: u16) u32 {
    return 0xFF00_0000 | (gun(word) << 16) | (gun(word >> 4) << 8) | gun(word >> 8);
}

fn gun(nibble: u16) u32 {
    const level: u32 = ((nibble & 7) << 1) | ((nibble >> 3) & 1);
    return level * 16;
}

/// The entry's x as the machine uses it (snapped to the bus grid).
pub inline fn entryX(e: u32) usize {
    return @as(usize, e >> 16) & ~@as(usize, memmap.BEAM_GRID - 1);
}

/// Paint `row` (W double-pixels, one u64 = one low-res pixel doubled) from
/// `bg`, switching colour at each accepted entry of `table[0..count]`.
pub fn paintLine(row: []u64, bg: u32, table: []const u32, count: u16) Line {
    const n = @min(@as(usize, count), @min(memmap.BEAM_MAX, table.len));
    var dropped: u32 = @intCast(count - n);
    var colour = bg;
    var from: usize = 0;
    var have_prev = false;
    for (table[0..n]) |e| {
        const x = entryX(e);
        if (x >= W or (have_prev and x < from + memmap.BEAM_MIN_GAP)) {
            dropped += 1;
            continue;
        }
        fill(row, from, x, colour);
        from = x;
        colour = stToRgba(@truncate(e));
        have_prev = true;
    }
    fill(row, from, W, colour);
    return .{ .bg = colour, .dropped = dropped };
}

/// [a, b) low-res pixels, each one 64-bit store (the pixel doubled).
pub inline fn fill(row: []u64, a: usize, b: usize, rgba: u32) void {
    @memset(row[a..b], @as(u64, rgba) | (@as(u64, rgba) << 32));
}
