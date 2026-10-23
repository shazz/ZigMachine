// --------------------------------------------------------------------------
// NEWSCHOOL 1: THE TUNNEL. The whole 400x280 overscan is a textured tube,
// redrawn every frame at 2x2 pixels (200x140 texels), the camera wandering
// inside it. An ST could not fill this many pixels a frame; ZIGGY does it with
// two table loads and two packed stores per pair of texels.
//
// TABLES (gen_tunnel.zig, built on the host): MAP gives each texel of a window
// bigger than the screen its angle and depth; moving the window moves the
// vanishing point (the camera wander). TEX is a 64x64 panel texture of 16
// levels, 4 KB, so it stays in the 4 KB D$ while MAP streams past.
//
// COLOUR: index = fog(depth) << 4 | texel, so the 256 entries are 16 texel
// levels x 16 fog levels, graded neon (navy, violet, magenta, cyan seams) and
// fading into the dark at the far end. The palette is rebuilt only when the
// fade or the beat flash changes it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const G = @import("gen_tunnel.zig");
const raster = @import("raster.zig");
const grade = @import("grade.zig");
const T = @import("timeline.zig");
const art = @import("anima_art");

const MAP32: [*]const u32 = @ptrCast(@alignCast(&art.tunnel_map));
const TEX: *const [G.TEX_N * G.TEX_N]u8 = &art.tunnel_tex;
const LEN = T.ROTO - T.TUNNEL;

// SHADE[d]: the fog level of depth d, already shifted to the high nibble.
const SHADE: [256]u8 = blk: {
    var t: [256]u8 = undefined;
    for (0..256) |d| {
        const far: i32 = @as(i32, @intCast(d)) - 24;
        const near: i32 = if (far > 0) far else 0;
        const lvl: i32 = 15 - @divTrunc(near * 15, 180);
        t[d] = @as(u8, @intCast(if (lvl > 0) lvl else 0)) << 4;
    }
    break :blk t;
};

// The neon ramp, texel level -> STE colour.
const RAMP = [16][3]u8{
    .{ 0, 0, 2 },  .{ 1, 0, 4 },   .{ 2, 0, 6 },   .{ 4, 0, 8 },
    .{ 6, 1, 10 }, .{ 8, 1, 11 },  .{ 10, 2, 12 }, .{ 12, 3, 13 },
    .{ 14, 4, 14 }, .{ 15, 6, 14 }, .{ 9, 10, 15 }, .{ 4, 13, 15 },
    .{ 2, 15, 15 }, .{ 8, 15, 15 }, .{ 13, 15, 15 }, .{ 15, 15, 15 },
};

var pal_key: u32 = 0xFFFF_FFFF;

pub fn enter(fb: *zg.LogicalFB, _: *zg.Blitter) void {
    raster.use(&.{});
    raster.timing(fb, true);
    raster.openAll();
    pal_key = 0xFFFF_FFFF;
}

/// Per frame, by depth: the texture row (v), the angle offset (the spin plus
/// the TWIST, an angle growing with depth that bends the tube) and the fog,
/// packed so a texel costs one table load: row << 16 | angle << 8 | fog.
var by_depth: [256]u32 = undefined;

pub fn draw(fb: *zg.LogicalFB, lt: u32) void {
    const white = grade.flash(lt, LEN);
    const key = white | @as(u32, grade.beat) << 8;
    if (key != pal_key) {
        pal_key = key;
        grade.build(fb.palette, &RAMP, white);
    }
    const v: u32 = lt *% 2 +% grade.surge(lt);
    const twist: i32 = (48 * trig.sin(lt *% (1 << 23))) >> 16; // the bend, +-48 a 256 depth
    for (0..256) |d| {
        const di: i32 = @intCast(d);
        const ang: u32 = @bitCast(@as(i32, @intCast(lt)) + ((di * twist) >> 6));
        by_depth[d] = (((@as(u32, @intCast(d)) +% v) & 63) << 22) | (ang & 63) << 8 | SHADE[d];
    }
    halves(@ptrCast(@alignCast(fb.fb)));
}

/// The top half computed, written to its 2x2 texels AND, turned by 180
/// degrees, to the bottom half (see gen_tunnel.zig).
fn halves(out: [*]u32) void {
    const ROW = zg.PHYSICAL_WIDTH / 4; // u32 words a pixel row
    for (0..G.HALF) |y| {
        const src = MAP32 + y * (G.VW / 2);
        const t0 = out + y * 2 * ROW;
        const b0 = out + (zg.PHYSICAL_HEIGHT - 2 - y * 2) * ROW + (ROW - 1);
        for (0..G.VW / 2) |k| {
            const e = src[k];
            const p0 = texel(e & 0xFFFF);
            const p1 = texel(e >> 16);
            const w = p0 * 0x0101 | p1 * 0x0101_0000;
            const m = p1 * 0x0101 | p0 * 0x0101_0000;
            t0[k] = w;
            t0[k + ROW] = w;
            (b0 - k)[0] = m;
            (b0 - k + ROW)[0] = m;
        }
    }
}

inline fn texel(e: u32) u32 {
    const t = by_depth[e >> 8];
    return @as(u32, TEX[(t >> 16) | ((e +% (t >> 8)) & 63)]) | (t & 0xF0);
}
