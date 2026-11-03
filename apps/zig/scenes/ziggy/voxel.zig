// --------------------------------------------------------------------------
// ZIGGY showcase, VOXEL: a Comanche-style landscape, 320 columns cast front to
// back over a 256x256 height map, each column drawn as vertical spans from the
// ground up (a y-buffer per column), then the sky above what the ground left.
// Every pixel of the picture area is written once a frame.
//
// Per step: the map position moves by the band's step vector (adds), the map
// index is tex2d, one load (height << 8 | colour), and the screen row is
// (camera height - ground) * (SCALE / z): ZM-X's mulsh16 (one instruction) or
// the plain rv32 64-bit product (mul + mulh + shifts). Same integers either
// way, so the two pictures are identical.
// KESTREL_NEXT_ISA.md's voxel256: 1.81 -> 0.74 Mc.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const zmx = @import("rom_sdk").zmx;
const trig = zg.fixtrig;
const maps = @import("maps.zig");

pub const ROWS: i32 = 184;
const HORIZON: i32 = 46;
const SCALE: i32 = 140; // screen rows per map unit of height at z = 1
const BANDS = 4; // z doubles its step each band: 1, 2, 4, 8 map units
const PER_BAND = 40;
const STEPS = BANDS * PER_BAND;

/// SCALE / z (Q16.16) of each step, and z itself (Q16.16), built once.
pub const Depth = struct {
    rz: [STEPS]i32 = undefined,

    pub fn init(self: *Depth) void {
        var z: i32 = 2 << 16;
        for (0..STEPS) |s| {
            self.rz[s] = @intCast(@divTrunc(@as(i64, SCALE) << 32, z));
            z += @as(i32, 1) << @intCast(16 + s / PER_BAND);
        }
    }
};

pub const Camera = struct { x: u32, y: u32, a: trig.Angle, h: i32 };

/// The camera at time t: forward along a slowly turning heading, 60 units above the ground.
pub fn camera(t: u32, h: []const u8, prev_h: i32) Camera {
    const a: trig.Angle = @bitCast(trig.sin(t *% 1_700_000) *% 9000); // a gentle weave, +/- ~50 degrees
    const x: u32 = t *% 49152; // 0.75 map units a frame (the map wraps)
    const y: u32 = @bitCast(trig.sin(t *% 900_000) * 40);
    const ground: i32 = h[((y >> 16) & 255) * 256 + ((x >> 16) & 255)];
    const want = ground + 60;
    const ch = if (prev_h == 0) want else prev_h + @divTrunc(want - prev_h, 8); // eased, no jolts
    return .{ .x = x, .y = y, .a = a, .h = ch };
}

/// The map the frame reads: height << 8 | colour, one u16 a texel (one D$ miss a step, not two).
pub fn merge(hmap: []const u8, cmap: []const u8, out: []u16) void {
    for (out, 0..) |*o, i| o.* = @as(u16, hmap[i]) << 8 | cmap[i];
}

/// Per-column state, kept between depth steps (cart RAM, not the stack).
pub const Columns = struct {
    rx: [320]i32 = undefined,
    ry: [320]i32 = undefined,
    u: [320]u32 = undefined,
    v: [320]u32 = undefined,
    ybuf: [320]i32 = undefined,
};

pub fn draw(fb: *zg.LogicalFB, d: *const Depth, map: []const u16, cols: *Columns, cam: Camera, use_zmx: bool) void {
    if (use_zmx) frame(true, fb, d, map, cols, cam) else frame(false, fb, d, map, cols, cam);
}

// Depth outer, columns inner (Comanche's own order): at one depth the 320 rays sit side by
// side on the map, so neighbouring columns read neighbouring texels and the D$ keeps them.
// (Column by column, each ray walked its own line across 128 KB of maps: ~3 Mc a frame.)
fn frame(comptime use_zmx: bool, fb: *zg.LogicalFB, d: *const Depth, map: []const u16, c: *Columns, cam: Camera) void {
    const fwd_x = trig.cos(cam.a);
    const fwd_y = trig.sin(cam.a);
    const px = fb.fb;
    const stride: usize = fb.stride;
    for (0..320) |col| {
        // The column's ray: forward + side * (col - 160) / 160 (a 90-degree field).
        const side: i32 = @divTrunc((@as(i32, @intCast(col)) - 160) << 16, 160);
        c.rx[col] = fwd_x - mul(use_zmx, fwd_y, side);
        c.ry[col] = fwd_y + mul(use_zmx, fwd_x, side);
        c.u[col] = cam.x +% @as(u32, @bitCast(c.rx[col] * 2));
        c.v[col] = cam.y +% @as(u32, @bitCast(c.ry[col] * 2));
        c.ybuf[col] = ROWS;
    }
    var s: usize = 0;
    for (0..BANDS) |b| {
        const sh: u5 = @intCast(b); // this band's step: 2^b map units
        for (0..PER_BAND) |_| {
            const rz = d.rz[s];
            for (0..320) |col| {
                const ybuf = c.ybuf[col];
                const t = map[texel(use_zmx, c.u[col], c.v[col])];
                c.u[col] +%= @bitCast(c.rx[col] << sh);
                c.v[col] +%= @bitCast(c.ry[col] << sh);
                const y = HORIZON + mul(use_zmx, cam.h - @as(i32, t >> 8), rz);
                if (y >= ybuf) continue;
                const top: usize = @intCast(@max(y, 0));
                const ink: u8 = @truncate(t);
                var r = top;
                while (r < ybuf) : (r += 1) px[r * stride + col] = ink;
                c.ybuf[col] = @intCast(top);
            }
            s += 1;
        }
    }
    for (0..320) |col| { // the sky over what the ground left: a ramp by row
        var r: usize = 0;
        while (r < c.ybuf[col]) : (r += 1) px[r * stride + col] = maps.SKY0 + @as(u8, @intCast(r * 47 / @as(usize, @intCast(ROWS))));
    }
}

inline fn texel(comptime use_zmx: bool, u: u32, v: u32) u32 {
    if (use_zmx) return zmx.zmTex2d(u, v, 5 | 5 << 3); // tex2d 256x256: (8-3) | (8-3) << 3
    return (((v >> 16) & 255) << 8) | ((u >> 16) & 255);
}

/// a * b >> 16 (Q16.16), signed: ZM-X's mulsh16, or the 64-bit product.
inline fn mul(comptime use_zmx: bool, a: i32, b: i32) i32 {
    if (use_zmx) return zmx.zmMulsh16(a, b);
    return @truncate((@as(i64, a) * b) >> 16);
}
