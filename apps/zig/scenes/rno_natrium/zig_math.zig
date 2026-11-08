// --------------------------------------------------------------------------
// NATRIUM ZIG mode: the pure maths, no ZigOS import (zig_math_test.zig runs
// it natively through apps/zig/scene_tests.zig).
//
//   tunnelEntry  one entry of the full-resolution tunnel map CHISEL MAP reads.
//                The original's 160x100 table ($144C8, 2x2-pixel cells) is, to
//                within a texel, u = 64 + angle * 64 / pi (128 a turn, 0 to the
//                left of the centre) and v = 64 + 512 / r (r in cells), centred
//                between cells 79/80 and 49/50; v reaches 128 at r = 8, which
//                is where the table's hole (entry 0, black) begins. In PIXELS
//                that is v = 64 + 1024 / r and a hole of radius 16. Integers
//                only: an octant atan table (comptime) and an integer sqrt, so
//                the map is built at the first Z press with no float.
//   boxShade     the 7 shades of the chunky box ($56492: two pixels a cell from
//                pens 0/4/8/12) as ONE true colour: the mean of the two pens.
//   envLevel     the 13 env-map levels ($EE1A: a 2x2 dither of pens 0/4/8/12
//                over the picture's planes 0/1, which are 0 under both objects)
//                as the mean of the four pens.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const st = @import("st.zig");

/// atan(k / 256) in 1/256ths of a tunnel texel (128 texels a turn), k = 0..256.
const ATAN: [257]u32 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [257]u32 = undefined;
    for (&t, 0..) |*e, k| {
        const a = std.math.atan(@as(f64, @floatFromInt(k)) / 256.0);
        e.* = @intFromFloat(@round(a * 128.0 * 256.0 / (2.0 * std.math.pi)));
    }
    break :blk t;
};

/// Q8 texels in a quarter turn (32 texels).
const QUARTER: u32 = 32 << 8;

/// atan2(dy, dx) as Q8 texels, 0 along +x, 128 << 8 a turn (dy grows down, as on screen).
pub fn angle(dx: i32, dy: i32) u32 {
    const ax: u32 = @abs(dx);
    const ay: u32 = @abs(dy);
    if (ax == 0 and ay == 0) return 0;
    // the first octant's angle, then fold
    const a = if (ay <= ax) ATAN[(ay * 256 + ax / 2) / ax] else QUARTER - ATAN[(ax * 256 + ay / 2) / ay];
    const q: u32 = if (dx >= 0) a else 2 * QUARTER - a; // left half mirrors
    return if (dy >= 0) q else (4 * QUARTER - q) % (4 * QUARTER);
}

/// sqrt(n), rounded to the nearest integer.
pub fn isqrt(n: u32) u32 {
    const r: u32 = std.math.sqrt(n);
    return if (n - r * r > r) r + 1 else r;
}

pub const HOLE_R2: u32 = 4 * 16 * 16; // the hole: r < 16 px, here in half-pixel units squared

/// The map entry for a pixel at (dx2, dy2) HALF-pixels from the tunnel's centre
/// (odd values: the centre lies between pixels): v << 8 | u, both 0..127.
/// Entries inside the hole are 0; the cart covers the hole with a black disc.
pub fn tunnelEntry(dx2: i32, dy2: i32) u16 {
    const r2: u32 = @intCast(dx2 * dx2 + dy2 * dy2);
    if (r2 < HOLE_R2) return 0;
    const r = isqrt(r2); // half pixels
    const v: u32 = (64 + 2048 / r) & 127; // 1024 / (r / 2)
    // 64 + angle, with angle 0 to the LEFT: the original's u is 0 there.
    const u: u32 = ((angle(dx2, dy2) + (64 << 8) + 128) >> 8) & 127;
    return @intCast(v << 8 | u);
}

/// The dot tunnel's map entry ($D670, part 1) for a pixel at (dx2, dy2) half
/// pixels from the centre: vq << 8 | u, u 0..15 the blob column, vq 0..127 the
/// blob row in QUARTER texels (so the scroll moves every host frame). The
/// $144C8 word holds U8 = 128 + angle 128/pi (256 a turn, 0 to the left) and
/// V8 = 128 + 1024 / r (r in cells, = 2048 / r in pixels); $C2DC reads
/// u = U8 & 15, v = (V8 + ((U8 >> 4) & 7) * 8) & 31: the octant term that
/// twists the rings into a spiral. Both survive a half turn (U8 + 128), so
/// the original's mirrored bottom half is this same formula below the centre.
/// The hole (r < 16 px, the table's zero entries) is entry 0, as there.
pub fn dotEntry(dx2: i32, dy2: i32) u16 {
    const w = dotWord(dx2, dy2);
    return dotTexel(w[0], w[1]);
}

/// The $144C8 word's two bytes at full resolution: U8, and V8 in quarters.
pub fn dotWord(dx2: i32, dy2: i32) [2]u32 {
    const r2: u32 = @intCast(dx2 * dx2 + dy2 * dy2);
    if (r2 < HOLE_R2) return .{ 0, 0 };
    const r8 = isqrt(16 * r2); // eighths of a pixel
    // 4 * V8: the table holds floor(128.75 + 1024 / r) (r in cells), to within one
    const v8q: u32 = (515 + 65536 / r8) & 1023;
    return .{ ((angle(dx2, dy2) + (64 << 8) + 64) >> 7) & 255, v8q };
}

/// $C2DC on (U8, 4 V8): u = U8 & 15, v = V8 + the octant term, in quarters.
pub fn dotTexel(u8_: u32, v8q: u32) u16 {
    const vq = (v8q + ((u8_ >> 4) & 7) * 32) & 127;
    return @intCast(vq << 8 | (u8_ & 15));
}

inline fn chan(c: u32, s: u5) u32 {
    return (c >> s) & 0xFF;
}

/// The RGBA mean of `n` palette pens.
fn mean(pal: *const [16]u16, pens: []const u4) u32 {
    var r: u32 = 0;
    var g: u32 = 0;
    var b: u32 = 0;
    for (pens) |p| {
        const c = st.stColor(pal[p]);
        r += chan(c, 0);
        g += chan(c, 8);
        b += chan(c, 16);
    }
    const n: u32 = @intCast(pens.len);
    return (0xFF << 24) | ((b + n / 2) / n) << 16 | ((g + n / 2) / n) << 8 | (r + n / 2) / n;
}

/// Plane bits (2, 3) -> pen.
inline fn pen(p2: u32, p3: u32) u4 {
    return @intCast((p2 << 2) | (p3 << 3));
}

/// Shade c (0..6) of the box: cell 0 of $56492 holds the plane-2 bits in the
/// high byte and the plane-3 bits in the low one, bit 7 the left pixel.
pub fn boxShade(pal: *const [16]u16, c: usize) u32 {
    const w: u32 = A.be16(A.chunky_lut, c & 7);
    const hi = w >> 8;
    const lo = w & 0xFF;
    const pens = [2]u4{ pen((hi >> 7) & 1, (lo >> 7) & 1), pen((hi >> 6) & 1, (lo >> 6) & 1) };
    return mean(pal, &pens);
}

/// Level l (0..12) of the env map: $EE1A entry l is [plane 2 even line, plane 2
/// odd, plane 3 even, plane 3 odd], two bits each, bit 1 the left pixel.
pub fn envLevel(pal: *const [16]u16, l: usize) u32 {
    const d = A.dither[l * 4 ..][0..4];
    var pens: [4]u4 = undefined;
    for (0..2) |par| for (0..2) |px| {
        const bit: u3 = @intCast(1 - px);
        pens[par * 2 + px] = pen((d[par] >> bit) & 1, (d[2 + par] >> bit) & 1);
    };
    return mean(pal, &pens);
}
