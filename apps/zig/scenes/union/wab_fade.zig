// --------------------------------------------------------------------------
// Union intro — the WAB logo's fade (eflogowab.js), precomputed (used by wab.zig).
//
// The fade scales the logo's palette by globalAlpha each frame: 1, 1.005, 1,
// 0.995 ... 0.02 (eflogowab.js:186-188, a float accumulator, so it is simulated,
// not written as k/200), each channel truncated, v * alpha in f64 (what
// zg.palette.scaleRange did: 765 soft-float f64 products a frame on KESTREL).
// Here the accumulator runs at compile time and each frame's alpha becomes a Q24
// integer K chosen so that (v * K) >> 24 IS @intFromFloat(v * alpha) for every v
// in 0..255 (checked below, or the build fails). A frame then writes only the
// palette entries its K changes.
// --------------------------------------------------------------------------
const zg = @import("zigos");

const ALPHA_INCR: f64 = 0.005; // eflogowab.js:138
pub const FRAMES: usize = 950 - 750; // the fade's frames, as wab.zig
const RENDERS: usize = 949 - 750; // the alpha steps after each render up to here, then holds
pub const NONE: u32 = 0xFFFF_FFFF; // the palette holds the logo's own colours, not a scale

const base = blk: {
    const pal = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_intro/wab_pal.dat"));
    var b: [256][3]u8 = undefined;
    for (&b, pal[0..256]) |*o, c| o.* = .{ c.r, c.g, c.b };
    break :blk b;
};

/// K[f]: the Q24 scale wab.zig's fade frame f (1..FRAMES-1) writes.
pub const K: [FRAMES]u32 = blk: {
    @setEvalBranchQuota(2_000_000);
    var k: [FRAMES]u32 = @splat(NONE);
    var alpha: f64 = 1; // eflogowab's this.alpha and this.alphaIncr
    var incr: f64 = ALPHA_INCR;
    for (1..FRAMES) |f| {
        if (f < RENDERS) { // stepAlpha, after each render
            alpha += incr;
            if (alpha > 0.99) incr = -ALPHA_INCR;
            if (alpha < 0.001) alpha = 0.001;
        }
        k[f] = exact(@max(0, @min(1, alpha))); // a globalAlpha above 1 is ignored: the clamp
    }
    break :blk k;
};

/// The Q24 K whose (v * K) >> 24 is trunc(v * kk) in f64 for every channel value.
fn exact(kk: f64) u32 {
    const k0: u32 = @intFromFloat(@floor(kk * 16777216.0));
    for ([_]u32{ k0, k0 + 1, k0 -| 1 }) |cand| {
        for (0..256) |v| {
            const want: u32 = @intFromFloat(@as(f64, @floatFromInt(v)) * kk);
            if ((v * cand) >> 24 != want) break;
        } else return cand;
    }
    @compileError("wab_fade: no Q24 scale truncates like the f64 one");
}

fn scaled(i: usize, k: u32) u32 {
    const c = base[i];
    const s = zg.Color{ .r = @intCast((c[0] * k) >> 24), .g = @intCast((c[1] * k) >> 24), .b = @intCast((c[2] * k) >> 24), .a = 255 };
    return s.toRGBA();
}

/// Scale entries 1..255 of `fb`'s palette by `k`, writing only what changes from
/// `held` (the scale it holds, NONE = all). Returns the scale it now holds.
pub fn apply(fb: *zg.LogicalFB, held: u32, k: u32) u32 {
    if (k == held) return k;
    for (1..256) |i| {
        const now = scaled(i, k);
        if (held == NONE or now != scaled(i, held)) fb.palette[i] = now;
    }
    return k;
}
