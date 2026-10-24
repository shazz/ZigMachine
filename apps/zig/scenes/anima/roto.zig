// --------------------------------------------------------------------------
// NEWSCHOOL 2: THE MELT. The "A" tile (gen_roto.zig) rotozoomed over the whole
// overscan at 2x2 pixels, every row pulled sideways by a travelling sine, and
// -- the idea of the part -- A PALETTE PER LINE: the HBL writes 16 colour
// registers on each of the 280 lines (raster.zig), so the same 16 light levels
// are a different hue on every line, sweeping down the screen: 4,480 colours
// a frame on a 256-colour plane, with no pixel touched for it.
//
// The pixel loop is one packed 8.8 add and a texel load a texel, and a packed
// store per pair of texels; the rotation, zoom and melt are set once a row.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const raster = @import("raster.zig");
const grade = @import("grade.zig");
const T = @import("timeline.zig");
const art = @import("anima_art");

const TEX: *const [64 * 64]u8 = &art.roto_tex;
const LEN = T.TORUS - T.ROTO;
const VW = 200;
const VH = 140;
const HUES = 32;

// HUE[h][level]: level 0 black, 1..8 dark to full hue h, 9..15 on to white.
const HUE: [HUES][16]u32 = blk: {
    @setEvalBranchQuota(50_000);
    var t: [HUES][16]u32 = undefined;
    for (0..HUES) |h| {
        const seg = h * 6 / HUES; // the colour wheel in six sextants
        const f: u32 = (h * 6 % HUES) * 255 / HUES;
        const rgb: [3]u32 = switch (seg) {
            0 => .{ 255, f, 0 },
            1 => .{ 255 - f, 255, 0 },
            2 => .{ 0, 255, f },
            3 => .{ 0, 255 - f, 255 },
            4 => .{ f, 0, 255 },
            else => .{ 255, 0, 255 - f },
        };
        for (0..16) |l| {
            var c: u32 = 0xFF00_0000;
            for (0..3) |g| {
                const lu: u32 = l;
                const v: u32 = if (lu <= 8) rgb[g] * lu / 8 else rgb[g] + (255 - rgb[g]) * (lu - 8) / 7;
                c |= v << @intCast(8 * g);
            }
            t[h][l] = c;
        }
    }
    break :blk t;
};

const ENTRIES = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };

pub fn enter(fb: *zg.LogicalFB, _: *zg.Blitter) void {
    raster.use(&ENTRIES);
    raster.timing(fb, true);
    raster.openAll();
}

pub fn draw(fb: *zg.LogicalFB, lt: u32) void {
    palettes(lt, grade.flash(lt, LEN));
    pixels(@ptrCast(@alignCast(fb.fb)), lt);
}

/// Each line's 16 colours: a hue drifting down the screen on a slow wave.
fn palettes(lt: u32, white: u32) void {
    for (0..raster.ROWS) |r| {
        const wave = trig.sin(@as(u32, @intCast(r)) *% (1 << 24) +% lt *% (1 << 25)) >> 13; // +-8
        const h: usize = @intCast(@as(u32, @bitCast(@as(i32, @intCast(r / 10 + lt / 3)) + wave)) % HUES);
        const row = &raster.lines[r];
        for (0..16) |l| {
            var c = HUE[h][l];
            if (white > 0) c = toWhite(c, white);
            if (row[l] != c) row[l] = c;
        }
    }
}

fn toWhite(c: u32, white: u32) u32 {
    var o: u32 = 0xFF00_0000;
    for (0..3) |g| {
        const v = c >> @intCast(8 * g) & 0xFF;
        o |= (v + (255 - v) * white / 16) << @intCast(8 * g);
    }
    return o;
}

fn pixels(out: [*]u32, lt: u32) void {
    const ang: u32 = lt *% (3 << 22) +% @as(u32, @bitCast(trig.sin(lt *% (1 << 23)) << 13));
    const zoom: i32 = 64000 + ((30000 * trig.sin(lt *% (5 << 22))) >> 16); // Q16 tile texels a screen texel
    const du: i32 = (trig.cos(ang) >> 8) * zoom >> 8;
    const dv: i32 = (trig.sin(ang) >> 8) * zoom >> 8;
    const cu: i32 = @intCast(lt *% (40 << 10)); // the camera drifts across the tiles
    const cv: i32 = @intCast(lt *% (25 << 10));
    const melt: i32 = 6 * @as(i32, @intCast(@min(lt, 240)));
    const ROW = zg.PHYSICAL_WIDTH / 4;
    const duv: u32 = (@as(u32, @bitCast(dv)) >> 8) << 16 | (@as(u32, @bitCast(du)) >> 8 & 0xFFFF);
    for (0..VH) |yy| {
        const y: i32 = @as(i32, @intCast(yy)) - VH / 2;
        const pull = (melt * trig.sin(@as(u32, @intCast(yy)) *% (3 << 24) +% lt *% (1 << 26))) >> 8; // Q16
        const u: u32 = @bitCast(cu - (VW / 2) * du - y * dv + pull);
        const v: u32 = @bitCast(cv - (VW / 2) * dv + y * du);
        // u and v as 8.8 in ONE register (v high, u low): one add a texel. The
        // carry out of u's integer part lands in v's lowest fraction bit: 1/256
        // of a texel, invisible.
        var uv: u32 = (v >> 8) << 16 | (u >> 8 & 0xFFFF);
        const r0 = out + yy * 2 * ROW;
        for (0..VW / 2) |k| {
            const p0: u32 = TEX[(uv >> 18 & 0xFC0) | (uv >> 8 & 63)];
            uv +%= duv;
            const p1: u32 = TEX[(uv >> 18 & 0xFC0) | (uv >> 8 & 63)];
            uv +%= duv;
            const w = p0 * 0x0101 | p1 * 0x0101_0000;
            r0[k] = w;
            r0[k + ROW] = w;
        }
    }
}
