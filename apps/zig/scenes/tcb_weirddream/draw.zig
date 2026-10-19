// --------------------------------------------------------------------------
// WEIRD DREAM: painting one frame onto the single plane, in go()'s order.
// Assets: tools/private_tools/tcb_weirddream_assets.py.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const motion = @import("motion.zig");
const TEXT = @import("text.zig").TEXT;

const splash_b = @embedFile("../../assets/screens/tcb_weirddream/splash.raw");
const font_b = @embedFile("../../assets/screens/tcb_weirddream/font.raw");
const sprite_b = @embedFile("../../assets/screens/tcb_weirddream/sprite.raw");
const logos_b = @embedFile("../../assets/screens/tcb_weirddream/logos.raw");
const logos_idx = @embedFile("../../assets/screens/tcb_weirddream/logos.idx");

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;
const KEY: u8 = 0xFF; // transparent in sprite.raw / logos.raw

// Stars are the TCB logo's colours (tools script: pal indices after the font
// and sprite). Found at comptime by colour so a regenerated palette can't drift.
pub const STAR_INK = [3]u8{ palIndex(224, 160, 160), palIndex(192, 96, 96), palIndex(128, 64, 64) };
const pal_b = @embedFile("../../assets/screens/tcb_weirddream/pal.dat");
fn palIndex(r: u8, g: u8, b: u8) u8 {
    @setEvalBranchQuota(10_000);
    for (1..256) |i| {
        if (pal_b[i * 4] == r and pal_b[i * 4 + 1] == g and pal_b[i * 4 + 2] == b) return @intCast(i);
    }
    @compileError("star colour missing from pal.dat");
}

comptime {
    if (splash_b.len != W * H) @compileError("splash.raw is not 320x200");
    if (font_b.len != FONT_W * 150) @compileError("font.raw is not 320x150");
    if (sprite_b.len != SPRITE_W * SPRITE_H) @compileError("sprite.raw is not 48x32");
    if (logos_idx.len != LOGO_FRAMES * 12) @compileError("logos.idx is not 150 frames");
    // keyed() slices logos_b[off..] without a runtime check: prove every frame fits.
    @setEvalBranchQuota(20_000);
    for (0..LOGO_FRAMES) |i| {
        const e = logoEntry(i);
        if (e.off + @as(usize, e.w) * e.h > logos_b.len) @compileError("logos.idx frame overruns logos.raw");
    }
}

/// dosplash(): the canvas was filled with colour 0, and draw n (1-based) has
/// laid the picture down to canvas row 80n-40, i.e. ST row 40n-20.
pub fn splash(fb: *LogicalFB, n: u32) void {
    const rows: usize = @min(H, @as(usize, n) * 40 -| 20);
    for (0..H) |y| {
        const dst = fb.fb[y * fb.stride ..][0..W];
        if (y < rows) @memcpy(dst, splash_b[y * W ..][0..W]) else @memset(dst, 0);
    }
}

var chisel: zg.Blitter = .{};

/// One CHISEL fill: the row-by-row memset was 64,000 bytes of CPU stores a frame.
pub fn clear(fb: *LogicalFB) void {
    chisel.init();
    chisel.fill(fb, 0, 0, @intCast(W), @intCast(H), 0);
}

// --------------------------------------------------------------------------
// The two zooming logos: frame `zoom` of the precalc, at its y parity
// --------------------------------------------------------------------------
const TCB_ZOOMS = 40; // prelogotcb: 2000 / 50 rows
const REP_ZOOMS = 35; // prelogorep: 1540 / 44 rows
const LOGO_FRAMES = (TCB_ZOOMS + REP_ZOOMS) * 2;
const REP_FIRST = TCB_ZOOMS * 2; // logos.idx: TCB 1..40 then REPLICANTS 1..35, x2 parities
// drawPart at canvas x 225 / 41, both odd: the bake halves column pairs (-1,0)..
const TCB_X: i32 = 112;
const REP_X: i32 = 20;

pub fn logos(fb: *LogicalFB, l: motion.Layout) void {
    if (l.tcb_on_top) {
        logo(fb, l.rep, REP_FIRST, REP_ZOOMS, REP_X);
        logo(fb, l.tcb, 0, TCB_ZOOMS, TCB_X);
    } else {
        logo(fb, l.tcb, 0, TCB_ZOOMS, TCB_X);
        logo(fb, l.rep, REP_FIRST, REP_ZOOMS, REP_X);
    }
}

const LogoEntry = struct { dx: i16, dy: i16, w: u16, h: u16, off: u32 };

fn logoEntry(i: usize) LogoEntry {
    const e = logos_idx[i * 12 ..][0..12];
    return .{
        .dx = std.mem.readInt(i16, e[0..2], .little),
        .dy = std.mem.readInt(i16, e[2..4], .little),
        .w = std.mem.readInt(u16, e[4..6], .little),
        .h = std.mem.readInt(u16, e[6..8], .little),
        .off = std.mem.readInt(u32, e[8..12], .little),
    };
}

fn logo(fb: *LogicalFB, l: motion.Logo, first: usize, zooms: u8, x: i32) void {
    // zoom is bounded by the motion formulas (TCB <= 40, REPLICANTS <= 35);
    // the explicit test keeps a changed formula from reading another logo's frame.
    if (l.zoom == 0 or l.zoom > zooms) return;
    const e = logoEntry(first + (@as(usize, l.zoom) - 1) * 2 + @as(usize, @intCast(l.top & 1)));
    keyed(fb, logos_b[e.off..], e.w, e.h, x + e.dx, (l.top >> 1) + e.dy);
}

// --------------------------------------------------------------------------
// Stars, scroller, sprites
// --------------------------------------------------------------------------
pub fn stars(fb: *LogicalFB, field: *const [motion.STARS]motion.Star) void {
    for (field) |star| {
        const x = motion.starX(star);
        if (x >= W) continue;
        fb.fb[@as(usize, star.y) * fb.stride + x] = STAR_INK[star.layer];
    }
}

const FONT_W: usize = 320;
const GLYPH_W: usize = 32;
const GLYPH_H: usize = 25;
const GLYPH_COLS: usize = 10;
const STREAM: i64 = @as(i64, TEXT.len) * GLYPH_W;

/// 25 rows, each read at its own table offset, cut into 40 blocks of 8 pixels
/// that each drop to their own row (screen.js:441-449). Font black is colour 0
/// and OPAQUE, so the band hides what is under it; only stream pixels before
/// the text starts, and the tab's cell, are left unpainted, as in CODEF.
pub fn scroller(fb: *LogicalFB, l: motion.Layout) void {
    for (0..GLYPH_H) |j| {
        const row_at = l.text_at + motion.scroll_off[(l.table_at + j) % motion.SCROLL_LEN];
        for (l.col_y, 0..) |top, c| {
            const dst = fb.fb[(@as(usize, top) + j) * fb.stride + c * 8 ..][0..8];
            block(dst, row_at + @as(i64, @intCast(c * 8)), j);
        }
    }
}

/// The 8 pixels of one block, glyph run by glyph run: a run is the rest of the stream's
/// current 32-px glyph (at most 8), copied whole from the font row. The old code looked
/// every pixel up again (an i64 modulo and two divides each). Pixels before the text, and
/// glyphs outside the 60 tiles, stay as they are.
fn block(dst: []u8, at: i64, row: usize) void {
    var done: usize = 0;
    while (done < 8) {
        const here = at + @as(i64, @intCast(done));
        const s: usize = if (here < 0) 0 else @intCast(@mod(here, STREAM));
        const n = if (here < 0) @min(8 - done, @as(usize, @intCast(-here))) else @min(8 - done, GLYPH_W - s % GLYPH_W);
        defer done += n;
        if (here < 0) continue;
        const ch = TEXT[s / GLYPH_W];
        if (ch < 32 or ch > 91) continue;
        const g: usize = ch - 32;
        const from = ((g / GLYPH_COLS) * GLYPH_H + row) * FONT_W + (g % GLYPH_COLS) * GLYPH_W + s % GLYPH_W;
        @memcpy(dst[done..][0..n], font_b[from..][0..n]);
    }
}

const SPRITE_W: u16 = 48;
const SPRITE_H: u16 = 32;

pub fn sprites(fb: *LogicalFB, l: motion.Layout) void {
    keyed(fb, sprite_b, SPRITE_W, SPRITE_H, 16, l.sprite_y[0]);
    keyed(fb, sprite_b, SPRITE_W, SPRITE_H, 256, l.sprite_y[1]);
}

/// A clipped blit that skips KEY. Clipping is worked out once per call.
fn keyed(fb: *LogicalFB, img: []const u8, w: u16, h: u16, x: i32, y: i32) void {
    const x0: i32 = @max(0, -x);
    const x1: i32 = @min(@as(i32, w), @as(i32, W) - x);
    const y0: i32 = @max(0, -y);
    const y1: i32 = @min(@as(i32, h), @as(i32, H) - y);
    if (x0 >= x1 or y0 >= y1) return;
    for (@as(usize, @intCast(y0))..@as(usize, @intCast(y1))) |r| {
        const src = img[r * w ..][@intCast(x0)..@intCast(x1)];
        const at = @as(usize, @intCast(y + @as(i32, @intCast(r)))) * fb.stride + @as(usize, @intCast(x + x0));
        for (src, fb.fb[at..][0..src.len]) |v, *p| {
            if (v != KEY) p.* = v;
        }
    }
}
