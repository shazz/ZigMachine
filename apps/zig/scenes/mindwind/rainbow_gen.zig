// --------------------------------------------------------------------------
// Part C's three interference images, generated at start-up as the demo does
// ($44A4 -> $4FF6 with the pixel functions $51B8 / $51C6 / $51DA), as one
// byte a pixel: 448 x 207, colour = f(x, y) & 15 (the demo spreads those four
// bits over the planes with roxl; same pixels).
//
// x runs 0..447 along a row, g is the 16-px group counter the loop keeps in
// d6 (27 down to 0), the table is the 1024-a-turn sine at $271C8.
//   ramp   ($51B8): (2 (y - x) sin[2x]) >> 16            (muls.w, add.l, swap)
//   waves  ($51C6): (2 ((y + 30) << 7) sin[50 + x]) >> 16
//   rings  ($51DA): (x + g)^2 + (y - 94)^2 / x
// The rings' first division, divu.w d4,d0, always divides by zero: the four
// lsr.w that pack the previous pixel's bits leave d4's low word 0, and TOS's
// zero-divide vector is a bare RTE, so it changes nothing; neither does the
// second one at x = 0. Both are kept as the no-ops they were.
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: usize = 448;
pub const H: usize = 207;
pub const IMAGE_BYTES: usize = W * H;
pub const Kind = enum(u2) { ramp, waves, rings };

inline fn sinAt(t: []const u8, i: usize) i32 {
    return std.mem.readInt(i16, t[2 * i ..][0..2], .big);
}

inline fn high(prod: i32) u8 {
    const v: u32 = @bitCast(prod *% 2);
    return @intCast((v >> 16) & 15);
}

fn pixel(kind: Kind, t: []const u8, x: usize, y: usize) u8 {
    const xi: i32 = @intCast(x);
    const yi: i32 = @intCast(y);
    switch (kind) {
        .ramp => {
            const d: i16 = @truncate(yi - xi);
            return high(@as(i32, d) * sinAt(t, 2 * x));
        },
        .waves => {
            const d: i16 = @bitCast(@as(u16, @intCast(yi + 30)) << 7);
            return high(@as(i32, d) * sinAt(t, 50 + x));
        },
        .rings => {
            const g: i32 = 27 - @as(i32, @intCast(x / 16));
            const s: i32 = xi + g;
            const sq: i32 = s * s; // muls.w d0,d0; divu.w by 0: no-op
            const dy: i32 = yi - 94;
            var d1: u32 = @bitCast(dy * dy); // muls.w d1,d1
            if (x != 0) { // divs.w d5,d1: remainder high, quotient low
                const n: i32 = @bitCast(d1);
                const q: u16 = @bitCast(@as(i16, @intCast(@divTrunc(n, xi))));
                const r: u16 = @bitCast(@as(i16, @intCast(@rem(n, xi))));
                d1 = @as(u32, r) << 16 | q;
            }
            const v: u32 = @as(u32, @bitCast(sq)) +% d1;
            return @intCast(v & 15);
        },
    }
}

/// One image into `out` (IMAGE_BYTES), rows of W bytes.
pub fn generate(kind: Kind, sine: []const u8, out: []u8) void {
    for (0..H) |y| {
        for (0..W) |x| out[y * W + x] = pixel(kind, sine, x, y);
    }
}
