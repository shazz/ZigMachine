// --------------------------------------------------------------------------
// RACER: a car's shadow on the plane (M5 step 3, Matt's ask). One quad a car on the ground
// (carmodel's shadow part), sorted right after the ground face under the car and before the car's
// own faces, then drawn by DARKENING what is already in the plane, span by span:
//
//   REAL (the default)  each pixel drops one level down its colour ramp. The plane holds palette
//                       indices 16 + ramp * 8 + level, so one level down is index - 1, except at a
//                       ramp's bottom (level 0 stays: never into the ramp below) and the first 16
//                       entries (sky, HUD, far ground, backdrop: not ramps, left alone).
//   FAKE (key y)        the arcade's checkerboard: every other pixel ((x + y) even) is DITHER
//                       (index 0, black), the others are left alone. No read.
//
// Both run four pixels a word (SWAR: the level and "is a ramp" tests on each byte at once), the
// row's unaligned head and tail a byte at a time: the board traps a misaligned word access.
// No ZigOS import: shadow_test.zig checks all 256 indices and both modes against byte-wise rules.
// --------------------------------------------------------------------------
pub const DITHER: u8 = 0;
pub var keep_from: u32 = 256; // M6: entries from here are the haze's pool (haze.zig), not ramps: left alone (a multiple of 8)
pub var fake: bool = false; // key y
pub var break_two: bool = false; // the harness' --break two (key S): two levels down (still clamped at the ramp's bottom)

/// One level down, as the plane's index: the ramp's bottom, the first 16 entries and the haze's pool stay.
pub fn darken(b: u8) u8 {
    return if (b >= 16 and b & 7 != 0 and b < keep_from) b - 1 else b;
}

const LO: u32 = 0x7F7F7F7F;
const TOP: u32 = 0x80808080;

/// darken() on the four bytes of a word at once (no byte borrows: a byte only drops where its level is >= 1).
pub fn darkenWord(w: u32) u32 {
    return darkenW(true, w, poolTop());
}

/// Each byte's (keep_from / 2 - 1) with its top bit set: darkenW's "index < keep_from" test (M6, the haze's pool).
fn poolTop() u32 {
    return ((keep_from >> 1) - 1) * 0x01010101 | TOP;
}

/// `pool` false: no haze pool (keep_from 256), the M5 word path exactly, at M5's cost.
inline fn darkenW(comptime pool: bool, w: u32, top: u32) u32 {
    const level = ((w & 0x07070707) + LO) & TOP; // bit 7 of a byte: level != 0 (level <= 7, so no carry out of the byte)
    const ramp = (((w >> 4) & 0x0F0F0F0F) + LO) & TOP; // ...: index >= 16
    if (!pool) return w - ((level & ramp) >> 7);
    const below = (top -% ((w >> 1) & LO)) & TOP; // ...: index < keep_from (no borrows: 0x80 + y - x > 0)
    return w - ((level & ramp & below) >> 7);
}

fn realByte(p: *u8) void {
    p.* = darken(p.*);
    if (break_two) p.* = darken(p.*);
}

fn realWords(comptime pool: bool, from: usize, to: usize) usize {
    const top = poolTop();
    var a = from;
    while (a + 4 <= to) : (a += 4) {
        const p: *u32 = @ptrFromInt(a);
        p.* = darkenW(pool, p.*, top);
        if (break_two) p.* = darkenW(pool, p.*, top);
    }
    return a;
}

/// Shade the pixels [x0, x1) of the row at `row` (the plane's address of pixel 0 of row y).
pub fn span(row: usize, y: i32, x0: i32, x1: i32) void {
    var a = row + @as(usize, @intCast(x0));
    const e = row + @as(usize, @intCast(x1));
    if (fake) {
        const par: usize = @intCast(@as(u32, @bitCast(y)) & 1); // pixel x is dithered when (x + y) is even
        while (a < e and a & 3 != 0) : (a += 1) fakeByte(a, row, par);
        // byte k of an aligned word is pixel x + k (little-endian): keep the bytes whose pixel is not dithered
        const keep: u32 = if ((a - row + par) & 1 == 0) 0xFF00FF00 else 0x00FF00FF;
        while (a + 4 <= e) : (a += 4) {
            const p: *u32 = @ptrFromInt(a);
            p.* = (p.* & keep) | (dither4 & ~keep);
        }
        while (a < e) : (a += 1) fakeByte(a, row, par);
        return;
    }
    while (a < e and a & 3 != 0) : (a += 1) realByte(@ptrFromInt(a));
    a = if (keep_from < 256) realWords(true, a, e) else realWords(false, a, e);
    while (a < e) : (a += 1) realByte(@ptrFromInt(a));
}

/// One level UP, as the plane's index (smoke, R82 bug pass): a ramp's top, the first 16 entries and the haze's pool stay.
pub fn lighten(b: u8) u8 {
    return if (b >= 16 and b & 7 != 7 and b < keep_from) b + 1 else b;
}

/// lighten() on the four bytes of a word at once (no byte carries: a byte only rises where its level is <= 6).
pub fn lightenWord(w: u32) u32 {
    const up = (((w & 0x07070707) ^ 0x07070707) + LO) & TOP; // bit 7 of a byte: level != 7
    const ramp = (((w >> 4) & 0x0F0F0F0F) + LO) & TOP; // ...: index >= 16
    const below = (poolTop() -% ((w >> 1) & LO)) & TOP; // ...: index < keep_from
    return w + ((up & ramp & below) >> 7);
}

/// Lighten the pixels [x0, x1) of the row at `row`: real transparency, no dither.
pub fn lightSpan(row: usize, x0: i32, x1: i32) void {
    var a = row + @as(usize, @intCast(x0));
    const e = row + @as(usize, @intCast(x1));
    while (a < e and a & 3 != 0) : (a += 1) @as(*u8, @ptrFromInt(a)).* = lighten(@as(*u8, @ptrFromInt(a)).*);
    while (a + 4 <= e) : (a += 4) {
        const p: *u32 = @ptrFromInt(a);
        p.* = lightenWord(p.*);
    }
    while (a < e) : (a += 1) @as(*u8, @ptrFromInt(a)).* = lighten(@as(*u8, @ptrFromInt(a)).*);
}

const dither4: u32 = @as(u32, DITHER) * 0x01010101;

inline fn fakeByte(a: usize, row: usize, par: usize) void {
    if ((a - row + par) & 1 == 0) @as(*u8, @ptrFromInt(a)).* = DITHER;
}
