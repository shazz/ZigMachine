// --------------------------------------------------------------------------
// NATRIUM ZIG mode, part 7: the $DB14 rotozoom over the whole overscan
// window, one CHISEL AFFINE op a frame (280 spans of 400 px) + the girl panel.
//
// The original's maths, every pixel instead of every 2x2 cell and both fields
// at once: angle SIN[3f/2], zoom z = $480 + 4 SIN[6f], X = sin * z, Y = cos * z
// (muls.w + lsr #8: here ZM-X mulsh16, one instruction on the board). Its
// texture steps, in texels a PIXEL:
//   across a line   dU = Y / 512   dV = X / 256
//   down a line     dU = -X / 512  dV = Y / 256
// (V moves twice as fast as U: the original stretches the skin, kept) from the
// box's top-left corner (ST x 144, line 20), where U = ($4000 - 32 Y) / 512 and
// V = $7FFE / 256 -- the original's V0 BUG kept too (chunky_box.zig: V0 is
// always $7FFE, only U is centred), so it turns about the same point. The
// spans carry that one plane across the whole window.
// f is the part's VBL count with the frame's fraction (Q10, zig_mode.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const zmx = @import("rom_sdk").zmx;
const R = @import("zig_res.zig");

/// The box's top-left corner in the window.
const BX: i32 = R.OX + 144;
const BY: i32 = R.OY + 20;

pub var spans: []v2.Span = &.{};

pub fn build() bool {
    spans = zg.mem.alloc(v2.Span, R.H) orelse return false;
    for (spans, 0..) |*s, y| s.* = .{ .x0 = 0, .x1 = R.W, .y = @intCast(y), .u0 = 0, .v0 = 0, .du = 0, .dv = 0 };
    return true;
}

/// X and Y of the original (sin * z >> 8, cos * z >> 8) at time t (Q10 VBLs).
pub fn xyAt(t: u32) [2]i32 {
    const z: i32 = 0x480 + (trig.sin(t *% (6 << 12)) >> 6); // 4 * SIN[6f], SIN = 256 * sin
    const a = t *% (3 << 11); // SIN index 3f / 2
    return .{ zmx.zmMulsh16(trig.sin(a), z), zmx.zmMulsh16(trig.cos(a), z) };
}

pub fn draw(fb: *zg.LogicalFB, t: u32) void {
    const xy = xyAt(t);
    const X = xy[0];
    const Y = xy[1];
    // Q16.16 texels a pixel
    const du: u32 = @bitCast(Y * 128);
    const dv: u32 = @bitCast(X * 256);
    const ru: u32 = @bitCast(-X * 128);
    const rv: u32 = @bitCast(Y * 256);
    // row 0, x 0: the box corner's U0, V0 moved back by (BX, BY) pixels
    var u: u32 = @as(u32, @bitCast((0x4000 - 32 * Y) * 128)) -% du *% @as(u32, BX) -% ru *% @as(u32, BY);
    var v: u32 = (0x7FFE * 256) -% dv *% @as(u32, BX) -% rv *% @as(u32, BY);
    for (spans) |*s| {
        s.u0 = u;
        s.v0 = v;
        s.du = du;
        s.dv = dv;
        u +%= ru;
        v +%= rv;
    }
    const tex = v2.Texture{ .pixels = R.skin, .stride = R.TEX, .umask = R.TEX - 1, .vmask = R.TEX - 1 };
    v2.affine(fb, tex, spans, .{});
    R.ops += 1;
    R.panel(fb, R.PANEL_P7);
}
