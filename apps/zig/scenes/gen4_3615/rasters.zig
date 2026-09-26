// --------------------------------------------------------------------------
// The screen's colour gradients, as REAL rasters: four palette entries the
// copper rewrites line by line (zg.copper, one HBL on the one plane).
//
// The remake draws them as pixels: the sky is a 2x90 canvas of skyColors used
// as a fill pattern, the VU meters are a 2x180 canvas of vueColors stretched
// over the bars with 'source-in', and the floor's far shadow is nine
// rgba(0,0,20,a) bands laid over the chessboard. Each is uniform along a line,
// i.e. one colour register per line on an ST, and skyColors / vueColors are
// written as ST register values (every nibble even: the 3-bit $0RGB doubled),
// so the colours are kept and only the mechanism changes.
//
// They are rendered the way this machine renders a colour register
// (machine/beam.zig stToRgba): a 4-bit level times 16, so an ST register's
// 3-bit gun lands on the nibble*32 grid, 0..224. The scene's own art palette
// is on that level*16 grid too (pal.dat: every channel a multiple of 16). The
// browser expands '#RGB' by 17 instead (#00E -> 238), a value no register makes.
// #045 / #0CE, the floor, follow the same rule (5 is an STE half-step, 80,
// which the art palette also uses). Only the shadow's rgba(0,0,20,a) blend is
// the remake's own arithmetic, kept as Chrome rounds it.
//
//
//   VU_INK       the bars, vueColors[k] for two lines of every three, black
//                on the third (the gap the 6-row stripes leave)
//   SKY_INK      the sky, skyColors[line - 135]
//   CHECK_DARK   the floor's two chessboard colours, #045 and #0CE, darkened
//   CHECK_LIGHT  line by line under the shadow bands, plain below them
//
// Each line changes at most two entries (floor lines), so the writes fit a
// line's budget many times over. None is colour 0: all four only exist inside
// the glyphs and the bars, so no raster reaches the borders.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const copper = zg.copper;
const Color = zg.Color;
const A = @import("assets.zig");
const S = @import("scroller.zig");

pub const SLOTS = [_]u8{ A.VU_INK, A.SKY_INK, A.CHECK_DARK, A.CHECK_LIGHT };
pub var tables: [SLOTS.len]copper.Table = undefined;

// screen.js:35-36, verbatim
const sky_colors = "00E.02E.04E.06E.08E.0AE.0CE.2EE.4EE.6EE.8EE.AEE.CEE.CCE.ECE.CCC.EEC.ECC.ECA.EEA.CEA.CE8.AE8.CE6.CE0.EE0.EE4.EE6.EEC.EE6.EE2.EE0.CE0.CE2.AE4.CE6.CEA.EEA.EC8.E88.E66.E40.A20.600.600";
const vue_colors = "E00.C02.A04.806.608.40A.20C.00E.02C.04A.068.086.0A4.0C2.0E0.2E0.4E0.6E0.8E0.AE0.CE0.EE0.EC2.EA4.E86.E68.E4A.E2C.E0E.C2E";
// damier(): damierShadow, damierAlpha, damierAlphaStep
const SHADOW_H = [_]usize{ 4, 4, 6, 6, 8, 8, 10, 12, 12 };
const SHADOW_ALPHA: f64 = 0.8;
const SHADOW_ALPHA_STEP: f64 = 0.09;
const SHADOW_RGB = [3]u8{ 0, 0, 20 };

pub const VU_TOP = 41; // vueCanView drawn at (58, 82), 180 rows
pub const VU_ROWS = 90;
pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

/// The remake's 'RGB' digits as 4-bit levels, times 16 (see the header).
fn level16(comptime c: []const u8) Color {
    const n = [3]u8{ hex(c[0]), hex(c[1]), hex(c[2]) };
    return .{ .r = n[0] * 16, .g = n[1] * 16, .b = n[2] * 16, .a = 255 };
}

fn hex(comptime d: u8) u8 {
    return std.fmt.charToDigit(d, 16) catch @compileError("bad colour digit");
}

fn list(comptime s: []const u8, comptime n: usize) [n]Color {
    var out: [n]Color = undefined;
    for (&out, 0..) |*c, i| {
        const e = s[i * 4 ..][0..3];
        // an ST register value: 3 bits a channel, written doubled
        for (e) |d| std.debug.assert(hex(d) % 2 == 0);
        c.* = level16(e);
    }
    std.debug.assert(s.len == n * 4 - 1);
    return out;
}

const sky = list(sky_colors, 45);
const vue = list(vue_colors, 30);
pub const check_dark = level16("045");
pub const check_light = level16("0CE");

/// fillRect(rgba(0,0,20,a)) over an opaque colour the way Chrome's raster
/// rounds it (all 36 shaded colours of a reference frame fit): an 8-bit alpha,
/// the source premultiplied and rounded, the destination scaled by (256-A)/256.
fn shade(c: Color, alpha: f64) Color {
    const a: u32 = @intFromFloat(@floor(alpha * 255 + 0.5));
    const dst = [3]u8{ c.r, c.g, c.b };
    var out: [3]u8 = undefined;
    for (&out, dst, SHADOW_RGB) |*o, d, s| o.* = @intCast((s * a * 2 + 255) / 510 + d * (256 - a) / 256);
    return .{ .r = out[0], .g = out[1], .b = out[2], .a = 255 };
}

/// The shadow over no floor at all (floor row 0 stops at x 704): the premultiplied
/// source over the page's black.
pub const shadow_bare: Color = shade(BLACK, SHADOW_ALPHA);

/// Fill the four tables once: every line of this screen is static colour.
/// `row0` is the physical row of ST canvas line 0.
pub fn build(fb: anytype, row0: usize) void {
    const vu_t = copper.table(fb, 0);
    for (0..VU_ROWS) |k| {
        const r = 2 * k; // vueCanView row: 4 rows of colour, 2 of gap, per 6
        vu_t[row0 + VU_TOP + k] = (if (r % 6 < 4) vue[r / 6] else BLACK).toRGBA();
    }
    const sky_t = copper.table(fb, 1);
    for (S.SKY_TOP..S.FLOOR_TOP) |Y| sky_t[row0 + Y] = sky[((2 * Y) % 90) >> 1].toRGBA();

    const dark_t = copper.table(fb, 2);
    const light_t = copper.table(fb, 3);
    var top: usize = 0; // canvas rows from 360
    var alpha = SHADOW_ALPHA;
    var band: usize = 0;
    for (S.FLOOR_TOP..S.BOX_Y + S.BOX_H) |Y| {
        const y = 2 * (Y - S.FLOOR_TOP);
        while (band < SHADOW_H.len and y >= top + SHADOW_H[band]) : (band += 1) {
            top += SHADOW_H[band];
            alpha -= SHADOW_ALPHA_STEP;
        }
        const shaded = band < SHADOW_H.len;
        dark_t[row0 + Y] = (if (shaded) shade(check_dark, alpha) else check_dark).toRGBA();
        light_t[row0 + Y] = (if (shaded) shade(check_light, alpha) else check_light).toRGBA();
    }
}
