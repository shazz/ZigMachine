// --------------------------------------------------------------------------
// grodan_kvack ZIG mode -- the pink layer ROTOZOOMED: one CHISEL v2 AFFINE op
// a frame, a span per overscan row (280 spans, 400 px each).
//
// The texture.  AFFINE wraps by AND masks, so it wants power-of-two sizes; the
// pink line-art tiles every 320 x 200.  So the tile is resampled ONCE, at
// init, to 512 x 256 (texel (U, V) = tile pixel (5U/8, 25V/32)), and the spans
// carry that non-uniform scale: a step of one tile pixel is 8/5 texel across,
// 32/25 down.  The rotation is a true rotation in TILE space, and the wrap is
// the tile's own period.  Texels are PINK or 0; the op is unkeyed, so its 0s
// clear the plane: no FILL a frame (the green plane shows through them).
//
// Per frame, integers only (CLAUDE.md): fixtrig angles, Q16.16 steps in
// wrapping u32 (the texture wraps at 2^16 texels, a multiple of 512 and 256,
// so modular arithmetic is exact), the centre panned by the original's X/Y.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const A = @import("assets.zig");
const model = @import("model.zig");
const L = @import("zig_layers.zig");

pub const TW = 512;
pub const TH = 256;
/// One turn every 1200 ticks (20 s); the zoom breathes every 450 ticks.
pub const ROT_STEP: u32 = 3_579_139; // 2^32 / 1200
pub const ZOOM_STEP: u32 = 9_544_372; // 2^32 / 450
/// Texels a screen pixel, Q16: 1 +/- 0.4 (0.6 = 1.67x zoomed in, 1.4 = out).
pub const ZOOM_AMP: i32 = 26_214; // 0.4

pub var tex: []u8 = &.{};
pub var spans: []v2.Span = &.{};

/// Build the texture and the span list in cart RAM; false when it is short.
pub fn build(pink: []const u8) bool {
    const m = zg.mem.mark();
    tex = zg.mem.alloc(u8, TW * TH) orelse return fail(m);
    spans = zg.mem.alloc(v2.Span, @intCast(L.H)) orelse return fail(m);
    // x0/x1/y never change: written once, so a frame stores only the four steps.
    for (spans, 0..) |*s, y| s.* = .{ .x0 = 0, .x1 = @intCast(L.W), .y = @intCast(y), .u0 = 0, .v0 = 0, .du = 0, .dv = 0 };
    for (0..TH) |v| {
        const ty = v * 25 / 32; // 0..199; row 199 is the period's blank row
        for (0..TW) |u| {
            const tx = u * 5 / 8;
            tex[v * TW + u] = if (ty < A.BG_H) pink[ty * A.BG_W + tx] else 0;
        }
    }
    return true;
}

fn fail(m: zg.mem.Mark) bool {
    zg.mem.release(m);
    tex = &.{};
    spans = &.{};
    return false;
}

/// The frame's matrix: the rotation angle and the Q16 texels-a-pixel scale.
pub fn angleAt(tick: u32) trig.Angle {
    return tick *% ROT_STEP;
}
pub fn scaleAt(tick: u32) i32 {
    return trig.ONE + trig.mul(trig.sin(tick *% ZOOM_STEP), ZOOM_AMP);
}

/// Fill the spans for this tick and pan, then one AFFINE onto `fb`.
pub fn draw(fb: *zg.LogicalFB, st: *const model.State, tick: u32) void {
    const k = scaleAt(tick);
    const a = trig.mul(trig.cos(angleAt(tick)), k); // tile px per screen px, x
    const b = trig.mul(trig.sin(angleAt(tick)), k); // ... y
    // Q16 texel steps: across a row (a, b), down a column (-b, a), scaled 8/5 x 32/25.
    const du: u32 = @bitCast(@divFloor(a * 8, 5));
    const dv: u32 = @bitCast(@divFloor(b * 32, 25));
    const ru: u32 = @bitCast(@divFloor(-b * 8, 5));
    const rv: u32 = @bitCast(@divFloor(a * 32, 25));
    // The tile pixel under the window's centre (200, 140): the original's pan
    // puts tile pixel (wx - 40 - X/2, wy - 40 - Y/2) at window pixel (wx, wy).
    const cu: u32 = @bitCast(@divFloor((160 - @divFloor(st.X, 2)) * (8 << 16), 5));
    const cv: u32 = @bitCast(@divFloor((100 - @divFloor(st.Y, 2)) * (32 << 16), 25));
    // Row 0, column 0: centre - 200 across - 140 down.
    var u: u32 = cu -% du *% 200 -% ru *% 140;
    var v: u32 = cv -% dv *% 200 -% rv *% 140;
    for (spans) |*s| {
        s.u0 = u;
        s.v0 = v;
        s.du = du;
        s.dv = dv;
        u +%= ru;
        v +%= rv;
    }
    v2.affine(fb, .{ .pixels = tex, .stride = TW, .umask = TW - 1, .vmask = TH - 1 }, spans, .{});
}
