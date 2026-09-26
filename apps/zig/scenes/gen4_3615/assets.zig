// --------------------------------------------------------------------------
// 3615 GEN4 assets: the layout of art.bin, the one shared palette, the
// scrolltext and the two tables screen.js precomputes in init()
// (tools/private_tools/gen4_3615_assets.py, gen4_3615_tables.mjs).
//
// Every PNG is 2x art on a clean (0,0) grid, so ST pixel (X, Y) is canvas pixel
// (2X, 2Y) and canvas image pixel (u, v) is halved pixel (u >> 1, v >> 1).
// 37 colours hold all the art unquantized; the raster inks sit above ART_MAX.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

const DIR = "../../assets/screens/gen4_3615/";

pub const palette = zg.convertU8ArraytoColors(@embedFile(DIR ++ "pal.dat"));

/// The palette entries the scene owns: four are raster inks the copper
/// rewrites per line, one is the bare shadow (see gen4_3615.zig).
pub const ART_MAX: u8 = 64;
pub const VU_INK: u8 = 64;
pub const SKY_INK: u8 = 65;
pub const CHECK_DARK: u8 = 66;
pub const CHECK_LIGHT: u8 = 67;
pub const SHADOW_BARE: u8 = 68;

const art = @embedFile(DIR ++ "art.bin");

fn cut(comptime at: usize, comptime w: usize, comptime h: usize) blit.Image {
    return blit.Image.init(art[at..][0 .. w * h], w);
}

// art.bin, in the asset script's order
pub const bord = cut(0, 12, 95);
pub const minitel = cut(1140, 39, 16);
pub const gen4 = cut(1764, 118, 36);
pub const whoelse = cut(6012, 236, 32);
pub const ulm = cut(13564, 142, 61);
pub const fate = cut(22226, 160, 56);
pub const moche = cut(31186, 12, 12);

comptime {
    std.debug.assert(art.len == 31186 + 12 * 12);
    std.debug.assert(1140 == 12 * 95 and 1764 - 1140 == 39 * 16 and 6012 - 1764 == 118 * 36);
    std.debug.assert(13564 - 6012 == 236 * 32 and 22226 - 13564 == 142 * 61 and 31186 - 22226 == 160 * 56);
}

/// ulm_font_192x178.png, halved to 96x89 glyphs, 1 bit a pixel, 12 bytes a row.
pub const FONT_W = 96;
pub const FONT_H = 89;
pub const FONT_GLYPHS = 60; // chars 32..91
pub const FONT_ROW_BYTES = FONT_W / 8;
pub const font: *const [FONT_GLYPHS * FONT_H * FONT_ROW_BYTES]u8 = @embedFile(DIR ++ "font.bin");

/// initDistort()'s ulmDistTable: the canvas x of a logo row, as Chrome computes it.
const ulm_bytes = @embedFile(DIR ++ "ulm_dist.bin");
pub const ULM_DIST_LEN = ulm_bytes.len / 2;
pub fn ulmDist(i: usize) i32 {
    return std.mem.readInt(u16, ulm_bytes[2 * i ..][0..2], .little);
}

/// mocheDist rounded to the column Chrome's nearest sampling takes.
pub const moche_dist: []const u8 = @embedFile(DIR ++ "moche_dist.bin");

// --------------------------------------------------------------------------
// The scrolltext, verbatim (screen.js:148), with its two scroller commands
// compiled to one byte each: ^CLogoFate; and ^CLogoWaveform;.
// --------------------------------------------------------------------------
pub const LOGO_FATE: u8 = 1;
pub const LOGO_WAVEFORM: u8 = 2;
pub const FONT_FIRST: u8 = 32;

const raw_text = @embedFile(DIR ++ "scrolltext.txt");

fn compileText() []const u8 {
    @setEvalBranchQuota(200_000);
    const commands = .{ .{ "^CLogoFate;", LOGO_FATE }, .{ "^CLogoWaveform;", LOGO_WAVEFORM } };
    var out: [raw_text.len]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    outer: while (i < raw_text.len) {
        inline for (commands) |c| {
            if (std.mem.startsWith(u8, raw_text[i..], c[0])) {
                out[n] = c[1];
                n += 1;
                i += c[0].len;
                continue :outer;
            }
        }
        const ch = raw_text[i];
        if (ch == '^') @compileError("scrolltext: a scroller command this port does not know");
        if (ch < FONT_FIRST or ch - FONT_FIRST >= FONT_GLYPHS) @compileError("scrolltext: a character the font has no glyph for");
        out[n] = ch;
        n += 1;
        i += 1;
    }
    const final = out[0..n].*;
    return &final;
}

pub const text: []const u8 = compileText();

comptime {
    // one LogoFate and thirteen LogoWaveform, none in the first six letters
    // (scrolltext.init loads those without looking for commands)
    @setEvalBranchQuota(100_000);
    var fates = 0;
    var waves = 0;
    for (text, 0..) |c, i| {
        if (c == LOGO_FATE) fates += 1;
        if (c == LOGO_WAVEFORM) waves += 1;
        if (c < FONT_FIRST) std.debug.assert(i >= 6);
    }
    std.debug.assert(fates == 1 and waves == 13);
}
