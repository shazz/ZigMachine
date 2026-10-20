// --------------------------------------------------------------------------
// THE REPLICANTS — "INTERNATIONAL KARATE PLUS" (IK+) cracktro.
//
// Ported from the Go/Ebitengine re-creation github.com/olivierh59500/go-dom-intro
// (vendored at prototypes/go-dom-intro/). That remake is the source of truth
// here: game.go's Update/Draw, its scrolltext, and its five ripped PNGs are
// reproduced, and where the remake faked the ST, the ST is done for real.
//
// THE SCREEN. Three layers over a scrolling raster background:
//
//   * a scrolltext that runs in FOUR sizes at once (one text, four rebuilds,
//     switched by "^CsN;" control codes as it scrolls), the active one drawn as
//     a repeating band of glyphs;
//   * the big REPLICANTS logo outline, 320x62 at content (0,18);
//   * eight little stars on a 32-pixel grid.
//
//   game.go's Draw order, once a frame: background slices, text (masked by the
//   rainbow), logo, then stars.
//
// REAL RASTERS, NOT SPRITES. rep_ik+_rast1.png is 2x200 and rep_ik+_rast2.png is
// 1x690, and every ROW of each is ONE solid colour (measured by
// tools/private_tools/ikplus_assets.py). The remake blits them as pictures; what
// they really are is colour TABLES, so here they are palette entries rewritten
// per scanline by the plane's HBL (ikplus/rasters.zig), running the full 400
// columns with every border open. Nothing of either raster is in the framebuffer.
//
// ONE PLANE, ONE PALETTE. Index 0 is the background raster colour (per line, or
// black outside the bands), 1 the scrolltext rainbow (per line), 2 the logo's
// grey, 3/4/5 the three star greys. The per-frame clear is a blitter fill of the
// content window; the text is comptime ink runs (libs/zig/effects/spans.zig), so
// the frame loop writes ink and never tests a key.
//
// HALVING. The remake canvas is 640x400 (ST 320x200 doubled) at (64,60) in a
// 768x540 window, and all of its art is 2x on a clean grid, so an ST pixel is
// canvas pixel (2X, 2Y) exactly. Every coordinate, size and speed is halved here
// (one exception, deliberately: the raster scroll positions stay at the remake's
// 2x units, because the two raster tables are kept at their 2x row counts and
// indexed by 2*t -- see rasters.zig).
//
// MUSIC. The remake plays assets/eliminator.ym, an LHA-packed YM5 register dump
// whose header names "Eliminator" / "Jochen Hippel (Jeroen Tel)". The project
// ships SNDH only, so the dump was matched against the archive by YM register
// comparison: Mad_Max/Demos/So_Watt/So_Watt_No_Crew.sndh (subtune 1) is
// bit-identical over 4000 frames, zero mismatches. It is already in docs/music/
// (shared with naos_nitrowave, which reused the same tune).
//
// KEYS. F1 / F2 step the scroll speed through {0.25, 0.5, 1, 2, 3, 4} x, exactly
// the remake's spinc. Escape (and Back) hand the screen back to the menu.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const spans = zg.spans;

const A = @import("assets.zig");
const text = @import("text.zig");
const rasters = @import("rasters.zig");
const stars = @import("stars.zig");

pub const PLANE = 0;

const MUSIC = "so_watt_no_crew.sndh";
const MUSIC_TUNE: u8 = 1;

const K_F1: u32 = 0xE001;
const K_F2: u32 = 0xE002;
const K_ESC: u32 = 0xE012;
const DIR_BACK: u8 = 6;

/// Fixed seed for the star field: the Go seeds from the clock, but the headless
/// harness must be able to predict every frame, so the generator is pinned here.
pub const STAR_SEED: u32 = 0x1C0FFEE;

// --- the four sizes, at 1x ------------------------------------------------
// BAND_Y is the content row after the remake's +2 merge shift: size0 at 2x y=2
// (+2 -> 4 -> ST 2), size1 at 2x 2, size2 at 2x 0 (+2 -> 2 -> ST 1), size3 at
// 2x 4 (+2 -> 6 -> ST 3).
const ACT_SCALE = [4]i32{ 1, 2, 4, 8 };
const ACT_SCALE_Y = [4]i32{ 1, 2, 4, 12 }; // size3 is 8 wide, 12 tall (game.go)
const BAND_Y = [4]i32{ 2, 2, 1, 3 };
const BAND_STEP = [4]i32{ 18, 33, 67, 67 }; // size3 has one band, so its step is unused
const BAND_COUNT = [4]i32{ 11, 6, 3, 1 };

/// ScrollText.speed = base * spinc, base {8,4,2,1} at 2x -> {4,2,1,0.5} at 1x,
/// in Q16.16.
const BASE_SPEED = [4]i64{ 4 << 16, 2 << 16, 1 << 16, 1 << 15 };
/// game.go's spinc, F1/F2 steps it through this list; the index is our state.
const SPINC = [6]i64{ 1 << 14, 1 << 15, 1 << 16, 2 << 16, 3 << 16, 4 << 16 };

const FONT = spans.build(A.font, A.FONT_W, 0);
const LOGO = spans.build(A.logo, A.LOGO_W, 0);

// --------------------------------------------------------------------------
// State. Module-level, like chonchon.zig, so the headless harness's testapi can
// read every word without a pointer into a struct instance.
// --------------------------------------------------------------------------
pub var off1: i64 = 320 << 16; // scrollText1.offset, 1x, Q16.16
pub var act_size: u2 = 0; // game.go's actSize
pub var spinc: u3 = 2; // index into SPINC (2 = 1.0)
pub var pos_y: u16 = 0; // game.go's posY, 0..652, even (+2 a frame)
pub var pos_y2: u16 = 200; // game.go's posY2, 1..200
pub var ok: bool = false;
pub var wants_quit: bool = false;
pub var blitter: zg.Blitter = .{};
pub var field: stars.Field = undefined;

/// off_k for scale k: the remake gives every size's offset as
/// baseOffset*scale + (1-scale)*canvasWidth, one canvas width of 320 at 1x.
fn offk(s: usize) i64 {
    const k: i64 = ACT_SCALE[s];
    return k * off1 - (k - 1) * 320 * 65536;
}

fn speed() i64 {
    return @divTrunc(BASE_SPEED[act_size] * SPINC[spinc], 65536);
}

/// ScrollText.advance(): wrap at -totalWidth, adding totalWidth + canvasWidth.
fn advance() void {
    off1 -= speed();
    const total: i64 = @as(i64, text.GLYPH_COUNT) * 20; // tileW * scaleX at 1x
    if (off1 <= -(total * 65536)) off1 += (total + 320) * 65536;
}

/// updateActSizeFromScroll(): the size is set by the glyph at the leading edge,
/// one glyph before it is visible, so a section is already the right size when
/// it scrolls in.  glyphPos is the same at every scale (the offsets scale with
/// tileW), which is why the offsets can be derived at all.
fn updateActSizeFromScroll() void {
    const s: usize = act_size;
    const tw: i64 = 20 * ACT_SCALE[s];
    const off = offk(s);
    var left: i64 = 0;
    if (off < 0) left = @divFloor(-off, tw * 65536);
    const visible: i64 = @divTrunc(320 + tw - 1, tw) + 1; // ceil(320/tw) + 1
    var gp: i64 = left + visible;
    if (gp >= @as(i64, text.GLYPH_COUNT)) gp = @as(i64, text.GLYPH_COUNT) - 1;

    var size: u2 = 0;
    for (text.CHANGES) |c| {
        if (@as(i64, c.pos) <= gp) size = c.size else break;
    }
    act_size = size;
}

// --------------------------------------------------------------------------
// Drawing into the content window of the overscan plane.
// --------------------------------------------------------------------------
inline fn contentRow(fb: *zg.LogicalFB, y: i32) usize {
    return (A.CONTENT_Y + @as(usize, @intCast(y))) * fb.stride + A.CONTENT_X;
}

/// Fill [x0,x1) of content row y with `color`, clipped to the content window.
inline fn fillRun(fb: *zg.LogicalFB, x0: i32, x1: i32, y: i32, color: u8) void {
    var a = x0;
    var b = x1;
    if (a < 0) a = 0;
    const w: i32 = @intCast(A.CONTENT_W);
    if (b > w) b = w;
    if (a >= b) return;
    const base = contentRow(fb, y) + @as(usize, @intCast(a));
    @memset(fb.fb[base..][0..@intCast(b - a)], color);
}

/// One glyph at content (x0, y0), scaled (kx, ky): the font's comptime row runs,
/// each source pixel a kx x ky block.
fn drawGlyph(fb: *zg.LogicalFB, g: i16, x0: i32, y0: i32, kx: i32, ky: i32) void {
    const base = @as(usize, @intCast(g)) * A.GLYPH_H;
    var r: usize = 0;
    while (r < A.GLYPH_H) : (r += 1) {
        const y = y0 + @as(i32, @intCast(r)) * ky;
        const y1 = y + ky;
        for (FONT.row(base + r)) |sp| {
            const xa = x0 + @as(i32, sp.x0) * kx;
            const xb = x0 + @as(i32, sp.x1) * kx;
            var yy = y;
            while (yy < y1) : (yy += 1) {
                if (yy < 0 or yy >= @as(i32, @intCast(A.CONTENT_H))) continue;
                fillRun(fb, xa, xb, yy, A.IDX_TEXT);
            }
        }
    }
}

/// ScrollText.drawAtOffset() at the active size, repeated down the content.
fn drawText(fb: *zg.LogicalFB) void {
    const s: usize = act_size;
    const kx = ACT_SCALE[s];
    const ky = ACT_SCALE_Y[s];
    const tw: i64 = 20 * kx;
    const off = offk(s);
    var first: i64 = 0;
    if (off < 0) first = @divFloor(-off, tw * 65536);
    if (first >= @as(i64, text.GLYPH_COUNT)) return;

    const tiles = &text.TILES[s];
    const x_end: i64 = @as(i64, @intCast(A.CONTENT_W)) * 65536;
    var xq: i64 = off + first * tw * 65536;
    var i: usize = @intCast(first);
    while (i < text.GLYPH_COUNT and xq < x_end) : (i += 1) {
        const g = tiles[i];
        if (g >= 0) {
            const x: i32 = @intCast(@divFloor(xq, 65536));
            var c: i32 = 0;
            while (c < BAND_COUNT[s]) : (c += 1) {
                drawGlyph(fb, g, x, BAND_Y[s] + c * BAND_STEP[s], kx, ky);
            }
        }
        xq += tw * 65536;
    }
}

/// The logo, its comptime ink runs, at content (0, LOGO_Y).
fn drawLogo(fb: *zg.LogicalFB) void {
    var r: usize = 0;
    while (r < A.LOGO_H) : (r += 1) {
        const y: i32 = @intCast(A.LOGO_Y + r);
        for (LOGO.row(r)) |sp| fillRun(fb, sp.x0, sp.x1, y, A.IDX_LOGO);
    }
}

// --------------------------------------------------------------------------
// The scene entry points (demo_main.zig's contract).
// --------------------------------------------------------------------------
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        ok = false;
        off1 = 320 << 16;
        act_size = 0;
        spinc = 2;
        pos_y = 0;
        pos_y2 = 200;
        wants_quit = false;
        blitter.init();
        field.init(STAR_SEED);

        // The ST's border is colour 0; black here, so the closed side borders
        // meet the open top and bottom ones. The rasters repaint entry 0 per
        // line once the borders are open.
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPaletteEntry(A.IDX_BG, Color.fromRGBA(A.BLACK));
        fb.setPaletteEntry(A.IDX_TEXT, Color.fromRGBA(A.BLACK));
        fb.setPaletteEntry(A.IDX_LOGO, Color.fromRGBA(A.LOGO_RGBA));
        fb.setPaletteEntry(A.IDX_STAR_DARK, Color.fromRGBA(A.STAR_DARK_RGBA));
        fb.setPaletteEntry(A.IDX_STAR_MID, Color.fromRGBA(A.STAR_MID_RGBA));
        fb.setPaletteEntry(A.IDX_STAR_BRIGHT, Color.fromRGBA(A.STAR_BRIGHT_RGBA));
        fb.openBorders(.all); // a raster runs edge to edge, so every border opens
        rasters.install(fb); // ... and the HBL repaints entries 0 and 1 per line
        fb.clearFrameBuffer(0);
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        ok = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt; // frame-based, like the remake: one step a rendered frame
        if (!ok) return;
        pos_y +%= 2;
        if (pos_y >= 654) pos_y = 0;
        pos_y2 -= 1;
        if (pos_y2 == 0) pos_y2 = 200;
        field.update();
        advance();
        updateActSizeFromScroll();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        if (!ok) return;
        const fb = &zigos.lfbs[PLANE];
        // The HBL reads the frame's scroll positions; publish them before the
        // machine renders (which is when the HBL actually runs).
        rasters.pos_y = pos_y;
        rasters.pos_y2 = pos_y2;
        blitter.fill(fb, @intCast(A.CONTENT_X), @intCast(A.CONTENT_Y), @intCast(A.CONTENT_W), @intCast(A.CONTENT_H), 0);
        drawText(fb);
        drawLogo(fb);
        field.draw(fb);
    }

    /// F1 / F2 are the remake's spinc steps; Escape and the host's Back return
    /// to the menu (declaring key() owns EVERY key, demo_main.zig's contract).
    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        switch (cp) {
            K_F1 => if (spinc + 1 < SPINC.len) {
                spinc += 1;
            },
            K_F2 => if (spinc > 0) {
                spinc -= 1;
            },
            K_ESC => wants_quit = true,
            else => {},
        }
    }

    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        if (dir == DIR_BACK) wants_quit = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};
