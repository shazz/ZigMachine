// --------------------------------------------------------------------------
// AURORA BOOT: the aurora's change masks added to the true-colour plane (tools/boot/aurora_mask.py).
//
// A container covers rows [row0, row0 + rows) of the band: row0 u8, rows u8, mask_len u16 LE, the mask (a bit a
// pixel, MSB = leftmost; 0x00 n = n zero bytes), then a nibble a changed pixel, low nibble first (0..14 =
// deltas[code], 15 = escape: the next two nibbles, low then high, are the index), a zero pad. Each changed pixel gets a
// 16-bit wrapping add; nothing else is touched, and there is no entropy decoder: the cost is a few cycles per
// changed pixel (ZX0 was ~85 % of the frame on the board). The codes end in a 12-byte zero pad (the baker's). Byte loads only (embedded data is not
// aligned; a misaligned wide load traps on the board). A malformed container stops at the first bad byte and
// answers false. No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: u32 = 320;
const ROW_BYTES: u32 = W / 8;
const ESC: u32 = 15;
const PAD_NIBBLES: u32 = 24; // the baker pads the codes with 12 zero bytes: the most one mask byte (8 pixels) reads

/// HIGH[b]: the position (0 = MSB = leftmost pixel) of b's highest set bit. A mask byte is walked one SET bit at a
/// time (about 2.3 a non-zero byte on the film) instead of testing all eight.
const HIGH: [256]u8 = blk: {
    var t: [256]u8 = undefined;
    for (&t, 0..) |*e, b| e.* = @clz(@as(u8, @intCast(b))) & 7; // comptime only: the cart never runs a clz
    break :blk t;
};

pub const Masked = struct {
    plane: [*]u16, // the displayed plane, stride W
    y0: u32, // the band's first screen row
    rows: u32, // the band's rows
    deltas: *const [256]u16, // padded with zeros: every escape byte indexes inside it

    pub fn apply(self: *const Masked, c: []const u8) bool {
        if (c.len < 4) return false;
        const row0: u32 = c[0];
        const rows: u32 = c[1];
        const mlen: u32 = @as(u32, c[2]) | @as(u32, c[3]) << 8;
        if (row0 + rows > self.rows or 4 + mlen > c.len) return false;
        const codes = c[4 + mlen ..];
        const nmax: u32 = @intCast(2 * codes.len);
        const px = self.plane + (self.y0 + row0) * W;
        const total = rows * ROW_BYTES;
        const mask = c[4..][0..mlen];
        var n: u32 = 0; // nibble cursor
        var at: u32 = 0; // mask byte = 8 pixels
        var i: u32 = 0;
        while (i < mlen) {
            const b: u8 = mask[i];
            i += 1;
            if (b == 0) {
                if (i >= mlen) return false;
                at += mask[i];
                i += 1;
                continue;
            }
            if (at >= total or n + PAD_NIBBLES > nmax) return false; // checked once per 8 pixels
            n = self.addByte(px + at * 8, b, codes, n);
            at += 1;
        }
        return at == total;
    }

    /// The 8 pixels at `p`: one delta per set bit of `b`, highest bit = leftmost; returns the nibble cursor.
    inline fn addByte(self: *const Masked, p: [*]u16, mask_byte: u8, codes: []const u8, n0: u32) u32 {
        var b = mask_byte;
        var n = n0;
        while (b != 0) {
            const k = HIGH[b];
            b ^= @as(u8, 0x80) >> @intCast(k);
            var v: u32 = nibble(codes, n);
            n += 1;
            if (v == ESC) {
                v = nibble(codes, n) | nibble(codes, n + 1) << 4;
                n += 2;
            }
            p[k] +%= self.deltas[v];
        }
        return n;
    }
};

inline fn nibble(src: []const u8, n: u32) u32 {
    return (src[n >> 1] >> @intCast((n & 1) << 2)) & 15;
}

// Two band rows; pixel 1 of row 0 gets code 0, pixel 9 an escaped code 16, row 1 nothing.
fn sample(out: []u8) []u8 {
    const head = [_]u8{ 0, 2, 4, 0 };
    @memcpy(out[0..4], &head);
    @memcpy(out[4..8], &[_]u8{ 0x40, 0x40, 0x00, 78 }); // bytes 0, 1 lit, then 78 zero bytes (rows end at 80)
    @memcpy(out[8..10], &[_]u8{ 0xF0, 0x10 }); // nibbles 0, 15, 0, 1 -> code 0, then escape 0x10
    @memset(out[10..22], 0); // the baker's pad
    return out[0..22];
}

test "a changed pixel adds its delta (16-bit, wrapping), an escape reaches the table's tail, the rest is untouched" {
    var plane = [_]u16{0xFFFF} ** (W * 2);
    var deltas = [_]u16{0} ** 256;
    deltas[0] = 2;
    deltas[16] = 0x0021;
    var buf: [24]u8 = undefined;
    const m = Masked{ .plane = &plane, .y0 = 0, .rows = 2, .deltas = &deltas };
    try std.testing.expect(m.apply(sample(&buf)));
    try std.testing.expectEqual(@as(u16, 1), plane[1]); // 0xFFFF + 2 wraps
    try std.testing.expectEqual(@as(u16, 0x0020), plane[9]);
    try std.testing.expectEqual(@as(u16, 0xFFFF), plane[0]);
    try std.testing.expectEqual(@as(u16, 0xFFFF), plane[W + 1]);
}

test "a malformed container is refused: short, past the band, a short mask, the codes' pad missing" {
    var plane = [_]u16{0} ** (W * 2);
    var deltas = [_]u16{0} ** 256;
    var buf: [24]u8 = undefined;
    const m = Masked{ .plane = &plane, .y0 = 0, .rows = 2, .deltas = &deltas };
    try std.testing.expect(!m.apply(&[_]u8{ 0, 2, 0 }));
    var c = sample(&buf);
    c[1] = 3; // three rows in a two-row band
    try std.testing.expect(!m.apply(c));
    c = sample(&buf);
    c[7] = 77; // one mask byte short of the rows
    try std.testing.expect(!m.apply(c));
    c = sample(&buf);
    try std.testing.expect(!m.apply(c[0..15])); // fewer than 24 nibbles left for a mask byte: refused before one is read
}
