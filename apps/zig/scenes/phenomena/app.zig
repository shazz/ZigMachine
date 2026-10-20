// --------------------------------------------------------------------------
// PHENOMENA — "ENIGMA" (1991) intro, ported from the Go/Ebitengine remake
// github.com/olivierh59500/phenomena-dna-scroll-intro (vendored at
// prototypes/go-phenomena/ as revision 8759087, the original before its DCK
// refactor; the refactor's presets are vendored too and agree).
//
// THE SCREEN. The remake is a 640x480 canvas of twelve states:
//
//   1  page 1: "FOR HOT VHS / AND SOFTWARE / SWAPPING, CONTACT / THE PUNISHER"
//      in black over a grey raster bar sliding down the screen
//   2  page 2: the PHENOMENA address, fading in and out (white on black)
//   3  the logo fading up, then a white silhouette fading back to the logo
//   4  the top purple raster bar appearing
//   5  the bottom purple raster bar appearing
//   6  a photon drop with decaying bounces
//   7  the photon fading to red
//   8  MAIN: logo, panel, two bars, the HSL photon, the DNA scroller, and a
//      navy rectangle retreating to reveal the bottom of the scroller
//   9-11 the logo, lower bar and upper bar fading out
//   12 black
//
// At 1x that is 320x240, placed at (40,20) in the 400x280 overscan plane; the
// borders are opened so a bar runs edge to edge.  The palette is 16 colours,
// with two real per-line registers (rasters.zig): the bar colours and the
// photon/DNA red.
//
// FIDELITY NOTE.  The remake's page-1 image is an opaque black Fill with the
// INVERTED (black) glyphs drawn on it, i.e. the raster bar and the text are
// both hidden.  That is plainly not what its "xor" page was for, so page 1
// here is the intended effect: the bar is a per-line grey raster and the black
// glyphs punch holes in it.  Everything else follows main.go's numbers.
//
// MUSIC.  music.ym in the remake is an LH5 archive around a YM6 dump:
// "Syntax Terror: TeX 24hours screen" by Jochen Hippel (converted by Jochen
// Knaus), 9248 frames at 50 Hz, loop 32.  That is the archive's
// Mad_Max/Demos/Syntax_Terror/Fletch.sndh ("Syntax Terror - TEX"): its
// subtune 1 equals the dump's registers 0..10 on every one of 6000 frames (2
// minutes, no offset; the other Syntax Terror tunes 0%), so the cart requests
// it as docs/music/syntax_terror_fletch.sndh and the 68000 replay runs on the
// sound CPU.  Up/Down volume keys have no host
// equivalent and are not mapped; Space/Enter (Fire) starts the outro at the
// same point as the remake's mouse click, Escape/Back leaves.
//
// One update and one draw a frame: every counter here is frame-based, exactly
// as the remake's Update/Draw, not dt-based.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const A = @import("assets.zig");
const P = @import("palette.zig");
const text = @import("text.zig");
const dna = @import("dna.zig");
const rasters = @import("rasters.zig");

pub const PLANE: usize = 0;

const MUSIC = "syntax_terror_fletch.sndh";

const K_ESC: u32 = 0xE012;
const DIR_FIRE: u8 = 5;
const DIR_BACK: u8 = 6;

pub const State = enum(u8) {
    text_page1,
    text_page2,
    show_logo,
    show_upper,
    show_lower,
    drop_photon,
    photon_fade,
    main,
    hide_logo,
    hide_lower,
    hide_upper,
    end,
};

// --- state, module-level so testapi.zig can read every word -----------------
pub var state: State = .text_page1;
pub var percent: i32 = 0;
pub var direction: i32 = 1;
pub var rasterbar_y: i32 = -20 << 16; // content 1x, Q16.16; -40 at 2x
pub var photon_y: i32 = 184 << 16; // 2x, Q16.16
pub var photon_gravity: i32 = 0; // 2x, Q16.16
pub var photon_bounce: i32 = -622592; // -9.50 at 2x
pub var t: i64 = 0; // Q16.16, +0.3 a frame
pub var color: i64 = 0; // Q16.16 hue counter, +1/3 a frame
pub var black_rect_w: i32 = 640; // 2x, -8 a frame
pub var black_rect_show: bool = true;
pub var finished: bool = false;

pub var ok: bool = false;
pub var wants_quit: bool = false;
pub var blitter: zg.Blitter = .{};

// --- text pages ------------------------------------------------------------
const Line = struct { y: usize, text: []const u8 };
const PAGE1 = [_]Line{
    .{ .y = 9, .text = "   FOR HOT VHS" },
    .{ .y = 38, .text = "  AND SOFTWARE" },
    .{ .y = 67, .text = "SWAPPING, CONTACT" },
    .{ .y = 110, .text = " THE PUNISHER " },
    .{ .y = 146, .text = "      AT..." },
};
const PAGE2 = [_]Line{
    .{ .y = 39, .text = "    PHENOMENA" },
    .{ .y = 79, .text = "   SKALDEV. 69" },
    .{ .y = 119, .text = "  16142 BROMMA" },
    .{ .y = 167, .text = "     SWEDEN!" },
};
const PAGE_X: usize = 24;
const PAGE_ADVANCE: usize = 16;

// --- drawing ---------------------------------------------------------------
inline fn contentRow(fb: *zg.LogicalFB, y: i32) usize {
    return (@as(usize, A.CONTENT_Y) + @as(usize, @intCast(y))) * fb.stride + A.CONTENT_X;
}

fn fillContent(fb: *zg.LogicalFB, x0: i32, x1: i32, y: i32, c: u8) void {
    if (y < 0 or y >= @as(i32, @intCast(A.CONTENT_H))) return;
    var a = x0;
    var b = x1;
    if (a < 0) a = 0;
    if (b > @as(i32, @intCast(A.CONTENT_W))) b = @as(i32, @intCast(A.CONTENT_W));
    if (a >= b) return;
    const base = contentRow(fb, y) + @as(usize, @intCast(a));
    @memset(fb.fb[base..][0..@intCast(b - a)], c);
}

/// The remake's screen.Fill(Black): the WHOLE plane, borders included.  (The
/// borders are opened, and show_logo paints them navy, so a content-only clear
/// would leave a navy frame around every later state.)
fn clearScreen(fb: *zg.LogicalFB) void {
    blitter.fill(fb, 0, 0, zg.PHYSICAL_WIDTH, zg.PHYSICAL_HEIGHT, A.IDX_BLACK);
}

/// A whole physical scanline of the overscan plane: raster bars cannot stop at
/// the content edge on an ST.
fn fillLine(fb: *zg.LogicalFB, phys_y: usize, c: u8) void {
    if (phys_y >= @as(usize, zg.PHYSICAL_HEIGHT)) return;
    const n: usize = fb.stride;
    @memset(fb.fb[phys_y * n ..][0..n], c);
}

fn drawGlyph(fb: *zg.LogicalFB, g: u8, x: usize, y: usize, c: u8) void {
    var row: usize = 0;
    while (row < A.FONT_H) : (row += 1) {
        const bits = A.glyphRow(g, row);
        if (bits == 0) continue;
        var col: usize = 0;
        while (col < A.FONT_W) : (col += 1) {
            if ((bits & (@as(u16, 1) << @intCast(col))) == 0) continue;
            const px = x + col;
            const py = y + row;
            if (px >= A.CONTENT_W or py >= A.CONTENT_H) continue;
            fb.fb[contentRow(fb, @intCast(py)) + px] = c;
        }
    }
}

fn drawPage(fb: *zg.LogicalFB, lines: []const Line, c: u8) void {
    for (lines) |line| {
        var x = PAGE_X;
        for (line.text) |ch| {
            drawGlyph(fb, text.fontIndex(ch), x, line.y, c);
            x += PAGE_ADVANCE;
        }
    }
}

fn drawIntroBar(fb: *zg.LogicalFB) void {
    const top = rasterbar_y >> 16;
    var d: usize = 0;
    while (d < A.BAR_INTRO_H) : (d += 1) {
        const y = top + @as(i32, @intCast(d));
        if (y < 0 or y >= @as(i32, @intCast(A.CONTENT_H))) continue;
        fillLine(fb, @as(usize, A.CONTENT_Y) + @as(usize, @intCast(y)), A.IDX_BAR);
    }
}

fn drawMainBars(fb: *zg.LogicalFB, top: bool, bottom: bool) void {
    if (top) {
        var r: usize = 0;
        while (r < A.BAR_ROWS) : (r += 1) fillLine(fb, A.CONTENT_Y + A.BAR_TOP_Y + r, A.IDX_BAR);
    }
    if (bottom) {
        var r: usize = 0;
        while (r < A.BAR_ROWS) : (r += 1) fillLine(fb, A.CONTENT_Y + A.BAR_BOTTOM_Y + r, A.IDX_BAR);
    }
}

fn drawMiddle(fb: *zg.LogicalFB) void {
    var y: i32 = @intCast(A.BAR_TOP_Y);
    while (y < @as(i32, @intCast(A.BAR_BOTTOM_Y))) : (y += 1) {
        fillContent(fb, 0, @intCast(A.CONTENT_W), y, A.IDX_MIDDLE);
    }
}

fn drawLogo(fb: *zg.LogicalFB) void {
    var y: usize = 0;
    while (y < A.LOGO_H) : (y += 1) {
        var x: usize = 0;
        while (x < A.LOGO_W) : (x += 1) {
            const v = A.logo[y * A.LOGO_W + x];
            if (v == 0) continue;
            fb.fb[contentRow(fb, @intCast(A.LOGO_Y + y)) + x] = v;
        }
    }
}

fn drawLogoShape(fb: *zg.LogicalFB, c: u8) void {
    var y: usize = 0;
    while (y < A.LOGO_H) : (y += 1) {
        var x: usize = 0;
        while (x < A.LOGO_W) : (x += 1) {
            if (A.logo[y * A.LOGO_W + x] == 0) continue;
            fb.fb[contentRow(fb, @intCast(A.LOGO_Y + y)) + x] = c;
        }
    }
}

fn drawPhoton(fb: *zg.LogicalFB, top: i32) void {
    var y: usize = 0;
    while (y < A.PHOTON_H) : (y += 1) {
        const py = top + @as(i32, @intCast(y));
        if (py < 0 or py >= @as(i32, @intCast(A.CONTENT_H))) continue;
        var x: usize = 0;
        while (x < A.PHOTON_W) : (x += 1) {
            if (A.photon[y * A.PHOTON_W + x] == 0) continue;
            fb.fb[contentRow(fb, py) + A.PHOTON_X + x] = A.IDX_RED;
        }
    }
}

// --- palette ---------------------------------------------------------------
inline fn q3(v: u32) u8 {
    const lvl: u32 = @min(@as(u32, 7), (v + 16) / 32);
    return @intCast(lvl * 32);
}

fn setBasePalette(fb: *zg.LogicalFB) void {
    var i: usize = 0;
    while (i < 16) : (i += 1) fb.setPaletteEntry(@intCast(i), zg.Color.fromRGBA(A.paletteRGB(i)));
}

/// main.go's logo draw: brightness p/100 for p<=100, then the white mask with
/// alpha (200-p)/100 over the full-brightness logo.  Whiten every logo colour
/// because the mask is exactly the logo's own silhouette.
fn setLogoPalette(fb: *zg.LogicalFB, brightness: u32, white: u32) void {
    var i: usize = 3;
    while (i < 15) : (i += 1) {
        var c: [3]u8 = undefined;
        for (0..3) |k| {
            const base: u32 = P.RGB[i][k];
            const lit = (base * @min(brightness, 100)) / 100;
            c[k] = q3(lit + ((224 - lit) * @min(white, 100)) / 100);
        }
        fb.setPaletteEntry(@intCast(i), zg.Color.fromRGBA(A.rgb3(c)));
    }
}

fn hueRGB(counter: i64) [3]u8 {
    var idx: usize = @intCast(@divTrunc(counter, 65536));
    if (idx > 359) idx = 359;
    return P.HUE[idx];
}

// --- the scene contract ----------------------------------------------------
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        ok = false;
        state = .text_page1;
        percent = 0;
        direction = 1;
        rasterbar_y = -20 << 16;
        photon_y = 184 << 16;
        photon_gravity = 0;
        photon_bounce = -622592;
        t = 0;
        color = 0;
        black_rect_w = 640;
        black_rect_show = true;
        finished = false;
        wants_quit = false;
        blitter.init();

        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all); // 400x280 plane, all borders opened by flicker
        setBasePalette(fb);
        rasters.install(fb);
        fb.clearFrameBuffer(0);

        dna.reset();
        dna.warmup();
        zg.requestSong(MUSIC);
        ok = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt; // frame-based, like the remake
        if (!ok) return;

        switch (state) {
            .text_page1 => {
                rasterbar_y += 49152; // +1.5 at 2x, +0.75 at 1x
                if (rasterbar_y >= 170 << 16) {
                    rasterbar_y = 0;
                    percent = 0;
                    state = .text_page2;
                }
            },
            .text_page2 => {
                percent += direction;
                if (percent > 200) {
                    direction = -1;
                    percent = 100;
                }
                if (percent <= 0 and direction == -1) {
                    percent = 0;
                    state = .show_logo;
                }
            },
            .show_logo => {
                percent += 4;
                if (percent >= 200) {
                    percent = 0;
                    state = .show_upper;
                }
            },
            .show_upper => {
                percent += 4;
                if (percent >= 100) {
                    percent = 0;
                    state = .show_lower;
                }
            },
            .show_lower => {
                percent += 4;
                if (percent >= 100) {
                    percent = 0;
                    state = .drop_photon;
                }
            },
            .drop_photon => {
                photon_gravity += 19661; // +0.30 at 2x
                photon_y += photon_gravity;
                if (photon_y > 445 << 16) {
                    photon_gravity = photon_bounce;
                    photon_bounce = @intCast(@divTrunc(@as(i64, photon_bounce) * 45875, 65536)); // *0.70
                }
                if (photon_bounce >= -45875) { // -0.70
                    percent = 100;
                    state = .photon_fade;
                }
            },
            .photon_fade => {
                percent -= 4;
                if (percent < 50) {
                    percent = 0;
                    state = .main;
                }
            },
            .main => {
                color += 21845; // +1/3
                if (color > 360 << 16) color = 0;

                if (!dna.pause) {
                    dna.scroll(dna.scroll_speed);
                } else {
                    dna.pause_time -= 1;
                    if (dna.pause_time == 0) {
                        dna.pause = false;
                        dna.rot_speed = dna.SPEED_RUN;
                        dna.scroll_speed = 1;
                    }
                }

                t += 19661; // +0.30
                dna.renderFrames(dna.rot_speed);

                if (black_rect_show) {
                    black_rect_w -= 8;
                    if (black_rect_w < 0) {
                        black_rect_w = 0;
                        black_rect_show = false;
                    }
                }

                if (finished) {
                    percent = 50;
                    direction = 1;
                    state = .hide_logo;
                }
            },
            .hide_logo => {
                if (direction > 0) {
                    percent += direction * 4;
                    if (percent > 100) direction = -1;
                } else {
                    percent += direction * 4;
                    if (percent < 0) {
                        percent = 100;
                        direction = -1;
                        state = .hide_lower;
                    }
                }
            },
            .hide_lower => {
                percent += direction * 4;
                if (percent < 0) {
                    direction = -1;
                    percent = 100;
                    state = .hide_upper;
                }
            },
            .hide_upper => {
                percent += direction * 4;
                if (percent < 0) state = .end;
            },
            .end => {},
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        if (!ok) return;
        const fb = &zigos.lfbs[PLANE];

        // Publish what the HBL will need before the machine paints.
        rasters.dna = state == .main;
        rasters.photon = false;
        rasters.alpha_top = 100;
        rasters.alpha_bottom = 100;
        rasters.mode = .off;

        switch (state) {
            .text_page1 => {
                rasters.mode = .intro;
                rasters.intro_y = rasterbar_y;
                clearScreen(fb);
                drawIntroBar(fb);
                drawPage(fb, &PAGE1, A.IDX_BLACK);
            },
            .text_page2 => {
                const b: u32 = if (percent <= 100) @intCast(percent) else @intCast(200 - percent);
                const v = q3(224 * b / 100);
                fb.setPaletteEntry(A.IDX_WHITE, zg.Color.fromRGBA(A.rgb(v, v, v)));
                clearScreen(fb);
                drawPage(fb, &PAGE2, A.IDX_WHITE);
            },
            .show_logo => {
                // The remake fills the whole 640x480 canvas with #000111; the
                // overscan borders are part of the screen here.
                var pl: usize = 0;
                while (pl < @as(usize, zg.PHYSICAL_HEIGHT)) : (pl += 1) fillLine(fb, pl, A.IDX_MIDDLE);
                if (percent <= 100) {
                    setLogoPalette(fb, @intCast(percent), 0);
                } else {
                    setLogoPalette(fb, 100, @intCast(200 - percent));
                }
                drawLogo(fb);
            },
            .show_upper, .show_lower, .drop_photon, .photon_fade, .main => {
                rasters.mode = .main;
                if (state == .show_upper) rasters.alpha_top = @intCast(percent);
                if (state == .show_lower) rasters.alpha_bottom = @intCast(percent);
                setBasePalette(fb);
                setLogoPalette(fb, 100, 0);

                clearScreen(fb);
                drawMiddle(fb);
                drawLogo(fb);
                drawMainBars(fb, true, state != .show_upper);
                if (state == .show_lower) {
                    // the bottom bar is drawn, alpha=percent, but the top is full
                    rasters.alpha_top = 100;
                }

                if (state == .drop_photon) {
                    rasters.photon = true;
                    rasters.photon_rgb = .{ 224, 224, 224 };
                    drawPhoton(fb, @divFloor(photon_y + 65536, 131072));
                } else if (state == .photon_fade) {
                    rasters.photon = true;
                    const p: u32 = @intCast(percent);
                    rasters.photon_rgb = .{ q3(224 * p / 100), q3(112 * p / 100), q3(112 * p / 100) };
                    drawPhoton(fb, @intCast(A.PHOTON_Y));
                } else if (state == .main) {
                    rasters.photon = true;
                    rasters.photon_rgb = hueRGB(color);
                    drawPhoton(fb, @intCast(A.PHOTON_Y));

                    dna.draw(fb, t);
                    if (black_rect_show) {
                        const w: i32 = @divTrunc(black_rect_w, 2);
                        var y: i32 = 187;
                        while (y < 215) : (y += 1) fillContent(fb, 0, w, y, A.IDX_MIDDLE);
                    }
                }
            },
            .hide_logo => {
                clearScreen(fb);
                if (direction > 0) {
                    setLogoPalette(fb, 100, @intCast(percent));
                    drawLogo(fb);
                } else {
                    fb.setPaletteEntry(A.IDX_WHITE, zg.Color.fromRGBA(A.rgb(
                        q3(224 * @as(u32, @intCast(percent)) / 100),
                        q3(224 * @as(u32, @intCast(percent)) / 100),
                        q3(224 * @as(u32, @intCast(percent)) / 100),
                    )));
                    drawLogoShape(fb, A.IDX_WHITE);
                }
            },
            .hide_lower => {
                rasters.mode = .main;
                rasters.alpha_top = 0;
                rasters.alpha_bottom = @intCast(percent);
                clearScreen(fb);
                drawMainBars(fb, false, true);
            },
            .hide_upper => {
                rasters.mode = .main;
                rasters.alpha_top = @intCast(percent);
                rasters.alpha_bottom = 0;
                clearScreen(fb);
                drawMainBars(fb, true, false);
            },
            .end => clearScreen(fb),
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        if (cp == K_ESC) wants_quit = true;
    }

    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        if (dir == DIR_BACK) wants_quit = true;
        if (dir == DIR_FIRE and state == .main) finished = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};
