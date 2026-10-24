// --------------------------------------------------------------------------
// OBJ demo: floor division without a divide for the small divisors a
// triangle edge has (its height in rows): one multiply by a reciprocal from a
// compile-time table, then one correction. ZIGGY's divide costs ~35 cycles,
// and the rasterisers need 2-3 a triangle. Exact (tests.zig checks it against
// @divFloor); numerators of 2^15 and more, or divisors past the table, divide.
// No ZigOS import.
// --------------------------------------------------------------------------
const RMAX = 256;

/// floor(2^16 / d) + 1, so n * R >> 16 is floor(n / d) or one off it.
const R: [RMAX]i32 = blk: {
    var t: [RMAX]i32 = undefined;
    t[0] = 0;
    for (1..RMAX) |d| t[d] = @divFloor(65536, @as(i32, @intCast(d))) + 1;
    break :blk t;
};

pub const QR = struct { q: i32, r: i32 };

/// q = floor(n / d), r = n - q * d (0 <= r < d), for d > 0.
pub inline fn floorDivRem(n: i32, d: i32) QR {
    if (d >= RMAX or n >= 32768 or n <= -32768) {
        const q = @divFloor(n, d);
        return .{ .q = q, .r = n - q * d };
    }
    var q = (n * R[@intCast(d)]) >> 16;
    var r = n - q * d;
    if (r < 0) {
        q -= 1;
        r += d;
    } else if (r >= d) {
        q += 1;
        r -= d;
    }
    return .{ .q = q, .r = r };
}
