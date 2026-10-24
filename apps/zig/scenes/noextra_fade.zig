// --------------------------------------------------------------------------
// NOEXTRA's intro fades without float on ZIGGY (see noextra.zig).
//
// The cart used to keep `fade` as an f32, add/subtract 0.01 a frame and scale
// the logos' palette by it (zg.palette.scaleRange). Both are replayed here at
// COMPILE time with the same f32 maths (Zig's comptime f32 rounds as the cart
// did), so the run only counts frames and indexes a table:
//   - fade in: the frames until the f32 sum passes 2.0 (200), each frame's
//     min(fade, 1) as an integer factor;
//   - fade out: from 1.0 down until it drops below 0 (100 frames).
// Each factor is a Q23 integer K picked so that (v * K) >> 23 equals the f32
// trunc(v * k) for EVERY channel value v = 0..255 (checked at comptime), so the
// palette is bit for bit the old one. v * K < 2^31: plain u32 maths.
//
// No ZigOS import: it tests natively through the scene tests' build.
// --------------------------------------------------------------------------
const STEP: f32 = 0.01; // CODEF's alpha step
pub const Q = 23;
pub const ONE: u32 = 1 << Q;

/// The Q23 factor whose integer scale matches the f32 one for every byte.
fn factor(comptime k: f32) u32 {
    @setEvalBranchQuota(100_000);
    const guess: i64 = @intFromFloat(@as(f64, k) * @as(f64, ONE));
    var d: i64 = -4;
    while (d <= 4) : (d += 1) {
        const kk: u32 = @intCast(@max(0, guess + d));
        var ok = true;
        for (0..256) |v| {
            const want: u32 = @intFromFloat(@as(f32, @floatFromInt(v)) * k);
            if ((@as(u32, @intCast(v)) * kk) >> Q != want) ok = false;
        }
        if (ok) return kk;
    }
    @compileError("noextra_fade: no Q23 factor reproduces this f32 fade step");
}

fn buildIn() []const u32 {
    @setEvalBranchQuota(10_000_000);
    var t: [256]u32 = undefined;
    var f: f32 = 0;
    t[0] = factor(0); // before the first update
    var n: usize = 1;
    while (true) : (n += 1) {
        f += STEP;
        if (f > 2.0) break;
        t[n] = factor(@min(f, 1.0));
    }
    const out = t[0..n].*;
    return &out;
}

fn buildOut() []const u32 {
    @setEvalBranchQuota(10_000_000);
    var t: [256]u32 = undefined;
    var f: f32 = 1.0;
    t[0] = factor(1.0); // the frame the bounce hands over
    var n: usize = 1;
    while (true) : (n += 1) {
        f -= STEP;
        if (f < 0.0) break;
        t[n] = factor(@min(f, 1.0));
    }
    const out = t[0..n].*;
    return &out;
}

/// IN[c]: the factor shown after c fade-in updates; the update that would make
/// c == IN.len is the one that ends the fade in. Same for OUT from the bounce.
pub const IN: []const u32 = buildIn();
pub const OUT: []const u32 = buildOut();

/// `c` with its RGB scaled by the Q23 factor `k` (alpha kept).
pub fn scale(c: anytype, k: u32) @TypeOf(c) {
    var o = c;
    o.r = @intCast((@as(u32, c.r) * k) >> Q);
    o.g = @intCast((@as(u32, c.g) * k) >> Q);
    o.b = @intCast((@as(u32, c.b) * k) >> Q);
    return o;
}
