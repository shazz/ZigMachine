// --------------------------------------------------------------------------
// ZIGGY showcase, ROTO: a rotozoom drawn by the CPU, every pixel of the
// picture area a frame (the CHISEL V2 cart does the same with the blitter's
// AFFINE op; this one is the cart CPU's own loop).
//
// Per pixel: u += du, v += dv (Q16.16, wrapping), the texel index, one load,
// one store. The texel index is ZM-X's tex2d (one instruction on the board)
// or its plain rv32 twin (srli, andi, srli, andi, slli, or): same index, so
// the two pictures are identical and only the cost moves. The texture size
// (64/128/256) changes the D$ footprint (4/16/64 KB) and nothing else.
// KESTREL_NEXT_ISA.md's roto128: 24.5 -> 9 cycles a pixel.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const zmx = @import("rom_sdk").zmx;
const trig = zg.fixtrig;

pub const ROWS: usize = 184; // rows 0..183; the HUD keeps 184..199

/// One frame at time `t`, for texture side 2^log, ZM-X on or off.
/// `angle`: the rotation (the cart turns it at the speed + / - set); `t` drives the zoom and the drift.
pub fn draw(fb: *zg.LogicalFB, tex: []const u8, log: u4, use_zmx: bool, t: u32, angle: trig.Angle) void {
    switch (log) {
        6 => if (use_zmx) frame(6, true, fb, tex, t, angle) else frame(6, false, fb, tex, t, angle),
        7 => if (use_zmx) frame(7, true, fb, tex, t, angle) else frame(7, false, fb, tex, t, angle),
        else => if (use_zmx) frame(8, true, fb, tex, t, angle) else frame(8, false, fb, tex, t, angle),
    }
}

fn frame(comptime log: u4, comptime use_zmx: bool, fb: *zg.LogicalFB, tex: []const u8, t: u32, angle: trig.Angle) void {
    // The camera: a turn every ~17 s, the zoom breathing between ~0.4 and ~2.3
    // texels a pixel, the centre drifting. Q16.16, scaled to the texture side so
    // every size shows the same picture.
    const a: trig.Angle = angle;
    const zoom: i32 = (3 << 15) + (trig.sin(t *% 2_900_000) * 5 >> 3) * 2;
    const side_scale: u5 = 8 - @as(u5, log); // the texture is 2^log, the picture is 256
    const du: i32 = trig.mul(trig.cos(a), zoom) >> side_scale;
    const dv: i32 = trig.mul(trig.sin(a), zoom) >> side_scale;
    const cu: i32 = (trig.sin(t *% 1_100_000) * 96) >> side_scale;
    const cv: i32 = (trig.cos(t *% 1_300_000) * 96) >> side_scale;
    // Row y starts at the centre minus 160 du (and 92 rows of the perpendicular).
    var ru: i32 = cu - 160 * du + 92 * dv;
    var rv: i32 = cv - 160 * dv - 92 * du;
    const px = fb.fb;
    const stride: usize = fb.stride;
    for (0..ROWS) |y| {
        var u: u32 = @bitCast(ru);
        var v: u32 = @bitCast(rv);
        const row = px + y * stride;
        for (0..320) |x| {
            row[x] = tex[texel(log, use_zmx, u, v)];
            u +%= @bitCast(du);
            v +%= @bitCast(dv);
        }
        ru -%= dv;
        rv +%= du;
    }
}

inline fn texel(comptime log: u4, comptime use_zmx: bool, u: u32, v: u32) u32 {
    if (use_zmx) return zmx.zmTex2d(u, v, comptime dims(log));
    const m: u32 = (1 << log) - 1;
    return (((v >> 16) & m) << log) | ((u >> 16) & m);
}

/// tex2d's funct7 for a square 2^log texture (libs/zig/zmx.zig texDims).
fn dims(comptime log: u4) u32 {
    return @as(u32, log - 3) | (@as(u32, log - 3) << 3);
}
