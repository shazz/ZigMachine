// --------------------------------------------------------------------------
// The slices' x, y and width from fate_fix.zig's fixed-point y and z, sorted
// by z (ties to the lower slice index), in integers only.
//
// The truncated numbers come from integer compares, not from dividing:
// trunc(120000 / D - 357) = n when 120000 >= (n + 357) D and 120000 < (n + 358) D
// (D = z + 200), and the like for y and the width; a divide of the values cut
// to Q12 only makes the first guess, which the compares then correct.
// --------------------------------------------------------------------------
const zorder = @import("zorder.zig");
const fate = @import("fate.zig");
const C = @import("fate_curve.zig");
const fix = @import("fate_fix.zig");

const SLICES = C.SLICES;
const ONE = fix.ONE;
const P = fix.P;

/// On the carpet and the sine z = (112 - i) / 10 does not move: x and the
/// width are worked out here at compile time, by fate_curve.zig's f64 maths.
const Still = struct { x: [SLICES]i32, l: [SLICES]i32 }; // not [SLICES]Slice: no padding to copy
const STILL: Still = blk: {
    @setEvalBranchQuota(10000);
    var t: Still = undefined;
    for (0..SLICES) |i| {
        const s = C.sliceOf(.{ .i = 0, .y = 0, .z = (112 - @as(f64, @floatFromInt(i))) / 10 });
        t.x[i] = s.x;
        t.l[i] = s.l;
    }
    break :blk t;
};

const Kind = enum { x, y, l };

/// The sign of value - b, scaled by D (x, y) or 5 (l):
/// x = 120000 / D - 357, y = 200 Y / D, l = 264 + 5.6 Z, D = Z + 200 > 0.
fn above(comptime kind: Kind, b: i32, p: P, d: i64) i64 {
    return switch (kind) {
        .x => 120000 * ONE - @as(i64, b + 357) * d,
        .y => 200 * p.y - @as(i64, b) * d,
        .l => 28 * p.z - 5 * @as(i64, b - 264) * ONE,
    };
}

/// trunc(value) from a guess within +-1: n when the value is in [n, n + 1)
/// above 0, (n - 1, n] below, (-1, 1) at 0.
fn trunc(comptime kind: Kind, guess: i32, p: P, d: i64) i32 {
    var n = guess;
    while (true) {
        if (n > 0 and above(kind, n, p, d) < 0) {
            n -= 1;
        } else if (n <= 0 and above(kind, n - 1, p, d) <= 0) {
            n -= 1;
        } else if (n >= 0 and above(kind, n + 1, p, d) >= 0) {
            n += 1;
        } else if (n < 0 and above(kind, n, p, d) > 0) {
            n += 1;
        } else return n;
    }
}

fn slice(wave: u8, i: usize, img: u8, p: P) C.Slice {
    const d = p.z + 200 * ONE; // > 0: z >= -20 on every curve
    const d12: i32 = @intCast(d >> 20);
    const y = C.TOP + trunc(.y, @divTrunc(200 * @as(i32, @intCast(p.y >> 20)), d12), p, d);
    if (wave >= 4) return .{ .i = img, .x = STILL.x[i], .y = y, .l = STILL.l[i] };
    const ex = @divTrunc(@as(i32, 120000 << 12), d12) - 357;
    const el = @divFloor((1320 << 12) + 28 * @as(i32, @intCast(p.z >> 20)), 5 << 12);
    return .{ .i = img, .x = trunc(.x, ex, p, d), .y = y, .l = trunc(.l, el, p, d) };
}

/// f's slices for this frame, in draw order.
pub fn place(f: *const fate.Fate, out: *[SLICES]C.Slice) void {
    var pos: [SLICES]P = undefined;
    var img: [SLICES]u8 = undefined;
    fix.positions(f.wave, fix.base(f), &pos, &img);
    var keys: [SLICES]u64 = undefined;
    for (&keys, pos) |*k, p| k.* = @as(u64, @bitCast(p.z)) ^ (1 << 63);
    var order: [SLICES]u8 = undefined;
    zorder.sortKeys(SLICES, &keys, &order);
    for (out, order) |*s, i| {
        const got = slice(f.wave, i, img[i], pos[i]);
        s.* = .{ .i = got.i, .x = got.x, .y = got.y, .l = got.l }; // field by field: a copy of
        // `got` also copies its padding, as byte and odd 16-bit stores (misaligned: they trap)
    }
}
