// --------------------------------------------------------------------------
// Part A's stripe lines, generated at start-up as the demo does ($3298-$340A,
// TEXT-relative in the depacked MINDWIND.TOS).
//
// A 128-row workspace of 416-px planar rows is drawn 16 times, each pass with
// a 16-px, 3-plane masked pattern (16 of them, stepping back from $317C)
// stamped right to left along every row at perspective x = x' - x'z/(z+11)
// + $9A0, z = 30, 28 .. 0, each row starting 2 units further left (the
// diagonal). After each pass every 4th workspace row is copied to the bank:
// 16 x 32 rows. Part A then shows, per scanline, one row of the bank or of the
// workspace (which keeps the last pass).
//
// The 68000 code is transcribed on its planar words (u16, bit 15 = leftmost
// pixel), including what it writes outside its own 16-px group, then turned
// into chunky rows; gen_test.zig checks the result against the RAM of the
// running demo, byte for byte. Integer only, init-time.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ROW_PX: usize = 416; // a 208-byte planar row
pub const ROW_WORDS: usize = ROW_PX / 4;
pub const WS_ROWS: usize = 128;
pub const BANK_ROWS: usize = 512;
pub const ROWS: usize = WS_ROWS + BANK_ROWS; // chunky: the workspace, then the bank
const MARGIN: usize = 16; // words before the workspace: the stamp writes 24 bytes left of its group
pub const PLANAR_WORDS: usize = MARGIN + ROWS * ROW_WORDS;

const Pattern = [4]u32; // mask, planes 0..2 (two 16-px groups each)

fn pattern(bytes: *const [256]u8, pass: usize) Pattern {
    const at = (15 - pass) * 16; // $317C - 16 * pass; the file starts at $317C - 15 * 16
    var p: Pattern = undefined;
    for (0..4) |i| p[i] = std.mem.readInt(u32, bytes[at + 4 * i ..][0..4], .big);
    return p;
}

inline fn lo(v: u32) u16 {
    return @truncate(v);
}
inline fn hi(v: u32) u16 {
    return @truncate(v >> 16);
}
inline fn andOrLong(w: []u16, at: usize, mask: u32, bits: u32) void {
    w[at] = (w[at] & hi(mask)) | hi(bits);
    w[at + 1] = (w[at + 1] & lo(mask)) | lo(bits);
}

/// $32FC-$336A: the pattern at pixel `px` of the row whose first word is `at`.
fn stamp(w: []u16, at: usize, px: u16, pat: Pattern) void {
    const s: u5 = @intCast(px & 15);
    var a1 = at + ((px >> 1) & 0xfff8) / 2 + 4;
    const m: u32 = @as(u32, 0xffff) >> s;
    const d7: u32 = m << 16 | m;
    const d6: u32 = ~d7;
    var d0 = std.math.rotr(u32, pat[0], s);
    var d1 = std.math.rotr(u32, pat[1], s);
    const d2r = std.math.rotr(u32, pat[2], s);
    var d3 = std.math.rotr(u32, pat[3], s);
    for ([3]u32{ d1, d2r, d3 }) |p| {
        w[a1] = (w[a1] & lo(d0)) | lo(p);
        a1 += 1;
    }
    a1 += 1;
    d1 = (d1 & 0xffff0000) | hi(d2r); // swap d2 / move.w d2,d1
    d3 &= 0xffff0000; // swap d4 / move.w d4,d3 (d4 = 0)
    d0 = (d0 & 0xffff0000) | hi(d0);
    const d4 = d0 | d6;
    d0 |= d7;
    andOrLong(w, a1, d0, d1 & d6);
    andOrLong(w, a1 + 2, d0, d3 & d6);
    a1 -= 8; // a1 +4 words, then lea -$18
    andOrLong(w, a1, d4, d1 & d7);
    andOrLong(w, a1 + 2, d4, d3 & d7);
}

/// One workspace row ($32C8-$3382): stamps right to left until x leaves the left edge.
fn drawRow(w: []u16, at: usize, start: u16, z: i16, pat: Pattern) void {
    var d5: u16 = start;
    while (true) : (d5 -%= 0x80) {
        const x: i16 = @bitCast(d5);
        const q: i16 = @intCast(@divTrunc(@as(i32, x) * z, @as(i32, z) + 11)); // muls / divs.w
        const d3: u16 = @as(u16, @bitCast(-%q)) +% d5 +% 0x9a0;
        if (d3 > 0xb40) continue; // bhi: past the right edge
        const s: i16 = @bitCast(d3 -% 0x800);
        if (s < 0) return; // blt: past the left edge, the row is done
        stamp(w, at, @as(u16, @bitCast(s)) >> 1, pat);
    }
}

/// The 16 passes into `w` (PLANAR_WORDS, scratch), then chunky rows into `out` (ROWS * ROW_PX).
pub fn generate(w: []u16, patterns: *const [256]u8, out: []u8) void {
    @memset(w, 0);
    var z: i16 = 0x20;
    var bank: usize = MARGIN + WS_ROWS * ROW_WORDS;
    for (0..16) |pass| {
        const pat = pattern(patterns, pass);
        z -= 2;
        var start: u16 = 0x898;
        for (0..WS_ROWS) |r| {
            drawRow(w, MARGIN + r * ROW_WORDS, start, z, pat);
            start -%= 2;
        }
        for (0..32) |k| {
            const src = MARGIN + 4 * k * ROW_WORDS;
            @memcpy(w[bank..][0..ROW_WORDS], w[src..][0..ROW_WORDS]);
            bank += ROW_WORDS;
        }
    }
    toChunky(w[MARGIN..][0 .. ROWS * ROW_WORDS], out);
}

/// Interleaved 4-plane groups (bit 15 = leftmost) to one byte a pixel.
pub fn toChunky(planar: []const u16, out: []u8) void {
    var g: usize = 0;
    while (g * 4 < planar.len) : (g += 1) {
        const p = planar[g * 4 ..][0..4];
        for (0..16) |b| {
            const bit: u4 = @intCast(15 - b);
            var c: u8 = 0;
            for (0..4) |k| c |= @as(u8, @intCast((p[k] >> bit) & 1)) << @intCast(k);
            out[g * 16 + b] = c;
        }
    }
}
