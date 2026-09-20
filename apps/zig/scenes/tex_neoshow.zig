// --------------------------------------------------------------------------
// The Exceptions (TEX) — "Super Neo Demo Show" (Atari ST, 1987; demozoo 76617),
// the first ST demo with the lower border removed (Alyssa's technique). Code: -ME-.
// Music: Rob Hubbard, programmed by Mad Max. Charset and pictures: ES.
//
// Ported from the CODEF HTML5 remake by Dyno (wab.com screen 473, 2016, CODEF MIT).
// Reference kept at prototypes/codef/473/. Assets, palettes, star frames and the
// scrolltext: tools/private_tools/tex_neoshow_assets.py -> tex_neoshow/tables.zig.
//
// One 416x276 canvas, redrawn every frame in the remake's order (anim()):
//   picture  fill black ('#444400' during Middle Earth), then a 320x200 NEOchrome
//            picture at (52, 29) with globalAlpha n/30 in, (209-n)/30 out. 210
//            black frames, then six pictures of 210 frames each, forever.
//            Einhorn: a star layer (einhorn_s1..5, round(n/10) % 5) under the
//            unicorn, both at the fade alpha. Middle Earth: a 46x18 shimmer
//            (round(n/8) % 4) at (326, 211), always at full alpha.
//   scroller '#220000' band at y 231, then a 320x16 canvas at (52, 231) holding two
//            6-row slices of gradient.png (stretched to 320 wide) at rows 2 and 8,
//            re-chosen every 12*60 frames: the old top slice moves down, a random
//            one of the 16 goes on top. Then the 32x16 font scrolling 4 px/frame.
//            Those slices are RASTERS here, not pixels — see "The scroller
//            rasters" below.
//   bottom   '#440000' from y 247, and a 38-row frame of bottom.png at (52, 248),
//            frame 11 - (round(iteration/3) % 12). The canvas ends at 276, so only
//            the top 28 rows of each frame are ever seen, in the remake too.
//
// Canvas alpha becomes palette blending: only one picture is up at a time, so 84
// slots hold its colours pre-blended over the fill for this frame's alpha. The
// einhorn slots are (unicorn ink, star colour) PAIRS, index e*7 + s, because a
// unicorn pixel at alpha a shows e*a + (s*a)*(1-a).
//
// Geometry: 416 wide into the 400x280 overscan plane: source columns 0..7 and
// 408..415 are cropped (only full-width fills live there; every image sits in
// 52..371). Rows sit at 2..277, the 2+2 spare rows transparent over black.
//
// THE SCROLLER RASTERS. gradient.png is ONE PIXEL WIDE and 96 tall, and every
// channel of all 96 rows is a multiple of 34 — the canonical 3-bit-per-channel
// Atari ST colour register rendered as nibble * 34. So it is not a picture: it
// is sixteen six-entry COLOUR TABLES, i.e. the values -ME- wrote to a colour
// register on twelve scanlines. The remake stretched that 1-px column to 320
// and blitted it; here zg.copper rewrites the register per scanline instead.
//
// TWO REGISTERS, AND HOW WIDE EACH ONE PAINTS. The demo opened only the LOWER
// border in 1987 (Matt, 2026-09-20), so the sides stayed closed — and yet the
// band still reaches both screen edges, because on the ST the border IS colour
// 0. The demozoo capture (media.demozoo.org/screens/s/75/ca/a758.138489.png,
// 384x270) shows both halves of that in pixels, sampled not eyeballed:
//   row 120 (picture)        x=2 and x=381 are (0,0,0)
//   rows 232..247 (band)     both edges (32,0,0), rows 248.. (64,0,0)
//   rows 234..238, 243..245  the GRADIENT rows: mid is (128,192,224) etc, and
//                            the edges are still (32,0,0) — the band colour
// So the band's own '#220000' is colour 0 and paints the border with it, while
// the twelve gradient lines are a NON-ZERO register and stop at the 320-pixel
// screen. That is exactly how they are built here: the band fills the raster
// with entry 0, whose colour the copper holds per line, and the gradient lines
// carry GRAD_INK inside the 320 box only. (vex/raster.zig's borderHbl drives
// colour 0 the same way, from the machine background on a 320-wide plane.)
//   This plane is 400 wide with the borders opened, so colour 0 is a plane
// entry here rather than the machine background: openBorders(.all) stays,
// because the port maps the remake's 416-wide canvas onto all 400 columns
// (content at plane 44..363) and closing the sides would crop the picture.
// --------------------------------------------------------------------------

const zg = @import("zigos");
const t = @import("tex_neoshow/tables.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const blit = zg.blit;

// Matt chose the SNDH over the screen's own neoshow.ym: Mad Max's 68000 replay of the
// same tune with digidrums (FLAG ~dy), which fits the scrolltext's "fantastic drums".
// Its drum timer starts through XBIOS Xbtimer, answered in sndh_player.zig.
const MUSIC = "auf_weidersehen_monty_digi.sndh";
const PLANE = 0;

const SCREEN_W: usize = 416; // screen_width
const SCREEN_H: usize = 276; // screen_height
const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const CROP_X: usize = (SCREEN_W - PW) / 2; // 8
const Y0: usize = (PH - SCREEN_H) / 2; // 2

// Palette layout (tex_neoshow_assets.py writes the static part).
const FILL: u8 = 1; // main_canvas.fill: black, or '#444400' for Middle Earth
const BAND: u8 = 2; // '#220000': the band's base colour, now colour 0's default
const BOTTOM_BG: u8 = 3; // '#440000'
const BOTTOM_BASE: u8 = 4;
const FONT_OFFSET: u8 = 9;
const SHIMMER_OFFSET: u8 = 25;
const GRAD_BASE: u8 = 30; // 96 gradient colours: the raster's source, never a pixel index
const PIC_BASE: u8 = 126;
const STAR_COLOURS: usize = 7;
/// The background/border register: the band's pixels carry it, and the copper
/// holds its colour per scanline. Transparent everywhere the band is not, so the
/// 2+2 spare rows stay as they were.
const BORDER_REG: u8 = 0;
/// The gradient's register: a NON-ZERO one, so its lines stop at the screen edge
/// (see the capture above). The first slot past the picture pairs, so nothing
/// else ever draws in it.
const GRAD_INK: u8 = PIC_BASE + 12 * @as(u8, @intCast(STAR_COLOURS)); // 210

const BLACK = [3]u8{ 0, 0, 0 };
const MIDEARTH_FILL = [3]u8{ 0x44, 0x44, 0x00 }; // '#' + color x4 + '00', color = round(1.0 * 4)

// Pictures: image.draw(main_canvas, 52, 29, alpha)
const PIC_X: usize = 52;
const PIC_Y: usize = 29;
const PIC_W: usize = 320;
const PIC_LEN: u32 = 210; // frames per picture
const FIRST_IMG: i32 = -210; // iteration_img: 210 black frames first
const FADE: f32 = 30;
const FADE_IN_END: u32 = 30;
const FADE_OUT_FROM: u32 = 179;
const FADE_OUT_END: f32 = 209;
const STAR_STEP: u32 = 10;
const STAR_FRAMES: u32 = 5;
const SHIMMER_X: usize = 326;
const SHIMMER_Y: usize = 211;
const SHIMMER_W: usize = 46;
const SHIMMER_H: usize = 18;
const SHIMMER_STEP: u32 = 8;
const SHIMMER_FRAMES: u32 = 4;

const Picture = enum { dragon, einhorn, midearth, moreta, porsche, tut_ench };
const SEQUENCE = [_]Picture{ .dragon, .einhorn, .midearth, .moreta, .porsche, .tut_ench };
const CYCLE: u32 = PIC_LEN * SEQUENCE.len; // 1260

// Scroller: scroll_canvas 320x16 at (52, 231), font.initTile(32, 16, 32), speed 4
const SCROLL_X: usize = 52;
const SCROLL_Y: usize = 231;
const SCROLL_W: usize = 320;
const SCROLL_H: usize = 16;
const FONT_W: i32 = 32;
const FONT_H: usize = 16;
const FONT_COLS: usize = 10; // font.png is 320 wide
const FONT_FIRST: u8 = 32;
const SPEED: i32 = 4;
const WIDE: i32 = (SCROLL_W + FONT_W - 1) / FONT_W + 1; // ceil(320 / 32) + 1
const LETTERS: usize = WIDE + 1; // letters 0..wide
const PRE_ROLL: usize = 88; // init's `for (i < 88) scrolltext.draw(0)`
const GRADIENT_PERIOD: u32 = 12 * 60;
const GRAD_SLICE: usize = 6;
const GRAD_SLICES: u32 = 16;
const GRAD_TOP: usize = 2;
const GRAD_LOW: usize = 8;

// Bottom: quad(0, 247, w, 38) and bottom.drawPart(main_canvas, 52, 247 + 1, ...)
const BOTTOM_Y: usize = 247;
const BOTTOM_IMG_Y: usize = 248;
const BOTTOM_FRAME_H: usize = 38;
const BOTTOM_FRAMES: u32 = 12;
const BOTTOM_STEP: u32 = 3;

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const DIR = "../assets/screens/tex_neoshow/";
const screen_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "screen_pal.dat"));
const einhorn_raw = @embedFile(DIR ++ "einhorn.raw");
const font_img = blit.Image.init(@embedFile(DIR ++ "font.raw"), SCROLL_W);
const bottom_img = blit.Image.init(@embedFile(DIR ++ "bottom.raw"), PIC_W);
const shimmer_img = blit.Image.init(@embedFile(DIR ++ "midearth_s.raw"), SHIMMER_W);

const Single = struct { raw: []const u8, pal: *const [16][3]u8 };

fn single(p: Picture) Single {
    return switch (p) {
        .dragon => .{ .raw = @embedFile(DIR ++ "dragon.raw"), .pal = &t.dragon_pal },
        .midearth => .{ .raw = @embedFile(DIR ++ "midearth.raw"), .pal = &t.midearth_pal },
        .moreta => .{ .raw = @embedFile(DIR ++ "moreta.raw"), .pal = &t.moreta_pal },
        .porsche => .{ .raw = @embedFile(DIR ++ "porsche.raw"), .pal = &t.porsche_pal },
        .tut_ench => .{ .raw = @embedFile(DIR ++ "tut_ench.raw"), .pal = &t.tut_ench_pal },
        .einhorn => unreachable,
    };
}

comptime {
    @setEvalBranchQuota(20_000);
    if (einhorn_raw.len != PIC_W * 200) @compileError("einhorn.raw is not 320x200");
    for (SEQUENCE) |p| if (p != .einhorn and single(p).raw.len != PIC_W * 200)
        @compileError("a picture .raw is not 320x200");
    for (t.star_frames) |frame| for (frame) |s| if (s.at >= PIC_W * 200)
        @compileError("a star lies outside the 320x200 picture");
    if (GRAD_BASE + GRAD_SLICES * GRAD_SLICE != PIC_BASE) @compileError("gradient slots do not end at PIC_BASE");
    // drawPicture fills only above the scroller: the band and bottom fills cover the rest
    if (SCROLL_Y + SCROLL_H != BOTTOM_Y or BOTTOM_Y >= SCREEN_H) @compileError("scroller and bottom no longer tile the lower screen");
    if (SHIMMER_Y + SHIMMER_H > SCROLL_Y or PIC_Y + 200 > SCROLL_Y) @compileError("picture reaches into the scroller");
    if (Y0 + SCROLL_Y + SCROLL_H > PH) @compileError("the scroller rasters fall outside the physical raster");
    if (bottom_img.h != BOTTOM_FRAME_H * BOTTOM_FRAMES) @compileError("bottom.raw is not 12 frames of 38");
    if (shimmer_img.h != SHIMMER_H * SHIMMER_FRAMES) @compileError("midearth_s.raw is not 4 frames of 18");
    if (PIC_BASE + 12 * STAR_COLOURS > 256) @compileError("picture slots overflow the palette");
    if (GRAD_LOW != GRAD_TOP + GRAD_SLICE) @compileError("the gradient slices are no longer one run");
    // every letter is a real tile, and there is no ^ command to interpret
    for (t.text) |c| if (c < FONT_FIRST or (c - FONT_FIRST) / FONT_COLS >= font_img.h / FONT_H or c == '^')
        @compileError("scrolltext character outside font.png");
}

// The composited unicorn + star frame (module scope: kept out of the Demo struct).
var einhorn_canvas: [PIC_W * 200]u8 = undefined;

// The scroller rasters: the band's and the gradient's colour for every PHYSICAL
// row (copper tables are
// always physical-row indexed, so opening the borders cannot shift them). One
// entry is all this screen drives, so copper's 4-slot cap is no constraint, and
// linepal is the wrong tool twice over: it allocates entries per row and its
// tables only cover the 200 VISIBLE rows, while rows 241..246 of this band sit
// in the opened lower border. The scene owns the table, so it weighs this cart
// alone.
const BORDER_SLOT: zg.copper.Slot = 0;
const GRAD_SLOT: zg.copper.Slot = 1;
var scroll_raster: [2]zg.copper.Table = undefined;
/// The physical row canvas row `y` lands on.
fn physRow(y: usize) usize {
    return Y0 + y;
}

const Letter = struct { x: i32, char: u8 };

/// Math.round(n / d) for n >= 0. Widened so 2n cannot wrap once `iteration`
/// passes 2^31 frames.
fn jsRound(n: u32, d: u32) u32 {
    return @intCast((2 * @as(u64, n) + d) / (2 * @as(u64, d)));
}

/// The fade of display_image / display_einhorn / display_midearth.
fn fadeAlpha(n: u32) f32 {
    if (n <= FADE_IN_END) return @as(f32, @floatFromInt(n)) / FADE;
    if (n >= FADE_OUT_FROM) return (FADE_OUT_END - @as(f32, @floatFromInt(n))) / FADE;
    return 1.0;
}

/// src drawn at globalAlpha a over dst.
fn over(src: [3]u8, dst: [3]u8, a: f32) [3]u8 {
    var out: [3]u8 = undefined;
    for (&out, src, dst) |*o, s, d| {
        const v = @as(f32, @floatFromInt(s)) * a + @as(f32, @floatFromInt(d)) * (1.0 - a);
        o.* = @intFromFloat(@round(v));
    }
    return out;
}

fn rgb(c: [3]u8) Color {
    return Color{ .r = c[0], .g = c[1], .b = c[2], .a = 255 };
}

fn fillRows(view: blit.Dst, y: usize, h: usize, index: u8) void {
    for (y..y + h) |row| @memset(view.buf[row * view.stride ..][0..view.w], index);
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    iteration: u32,
    iteration_img: i32,
    rng: u32,
    col1: u32, // gradient slice rows (party), multiples of 6
    col2: u32,
    letters: [LETTERS]Letter,
    scroffset: usize,
    // this frame's state, set by update() for render()
    picture: ?Picture,
    pic_n: u32,
    bottom_row: usize,
    einhorn_star: ?u32, // star frame einhorn_canvas holds

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here.
        self.iteration = 0;
        self.iteration_img = FIRST_IMG;
        self.rng = 0x0473_1987;
        self.col1 = 0;
        self.col2 = 0;
        self.scroffset = 0;
        for (&self.letters, 0..) |*l, i| {
            l.* = .{ .x = WIDE * FONT_W + @as(i32, @intCast(i)) * FONT_W, .char = t.text[self.scroffset] };
            self.scroffset += 1;
        }
        for (0..PRE_ROLL) |_| self.scrollStep();
        self.picture = null;
        self.pic_n = 0;
        self.bottom_row = 0;
        self.einhorn_star = null;

        zg.requestSong(MUSIC);
        zigos.setBackgroundColor(rgb(BLACK));
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all);
        fb.setPalette(screen_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        // Replaces openBorders()'s flicker handler with one that flickers AND
        // plays the rasters: a plane has one HBL and this screen needs both.
        // Installed after entry 0 is made transparent, so every row starts there.
        zg.copper.install(fb, &.{ BORDER_REG, GRAD_INK }, &scroll_raster, .{ .flicker = true });
        // Colour 0 is '#220000' down the band and the transparent entry
        // install() snapshotted everywhere else, so the spare rows are untouched.
        const border = zg.copper.table(fb, BORDER_SLOT);
        for (SCROLL_Y..SCROLL_Y + SCROLL_H) |y| border[physRow(y)] = fb.palette[BAND];
        fb.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.calcScrollBackground(&zigos.lfbs[PLANE]);
        if (self.iteration_img < 0) {
            self.picture = null;
        } else {
            const m: u32 = @intCast(@mod(self.iteration_img, @as(i32, CYCLE)));
            self.picture = SEQUENCE[m / PIC_LEN];
            self.pic_n = m % PIC_LEN;
        }
        self.scrollStep();
        self.bottom_row = BOTTOM_FRAME_H * (BOTTOM_FRAMES - 1 - jsRound(self.iteration, BOTTOM_STEP) % BOTTOM_FRAMES);
        self.iteration +%= 1;
        self.iteration_img +%= 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const view = blit.Dst.plane(fb).window(0, Y0, PW, SCREEN_H);
        self.drawPicture(fb, view);
        self.drawScroller(view);
        fillRows(view, BOTTOM_Y, SCREEN_H - BOTTOM_Y, BOTTOM_BG);
        const frame = blit.Rect{ .x = 0, .y = self.bottom_row, .w = PIC_W, .h = BOTTOM_FRAME_H };
        blit.blit(view, bottom_img, frame, PIC_X - CROP_X, BOTTOM_IMG_Y, null, .{ .offset = BOTTOM_BASE });
    }

    /// calc_scroll_background: two gradient slices, re-chosen every 12 s. The
    /// slice rows are the raster's colours, read straight out of the palette
    /// entries the asset already carries them in.
    fn calcScrollBackground(self: *Demo, fb: *const LogicalFB) void {
        if (self.iteration % GRADIENT_PERIOD != 0) return;
        if (self.iteration == 0) {
            self.col1 = 6;
            self.col2 = 0;
        } else {
            self.col2 = self.col1;
            self.rng ^= self.rng << 13; // xorshift32 stands in for Math.random()
            self.rng ^= self.rng >> 17;
            self.rng ^= self.rng << 5;
            self.col1 = (self.rng >> 28) % GRAD_SLICES * GRAD_SLICE;
        }
        const rows = zg.copper.table(fb, GRAD_SLOT);
        const top: usize = GRAD_BASE + @as(usize, self.col1);
        const low: usize = GRAD_BASE + @as(usize, self.col2);
        for (0..GRAD_SLICE) |k| {
            rows[physRow(SCROLL_Y + GRAD_TOP + k)] = fb.palette[top + k];
            rows[physRow(SCROLL_Y + GRAD_LOW + k)] = fb.palette[low + k];
        }
    }

    /// scrolltext_horizontal.draw's position update (the text has no ^ commands).
    /// Letters sit exactly one tile apart and never overlap, so its sort by x
    /// before drawing changes nothing and is not carried over.
    fn scrollStep(self: *Demo) void {
        for (&self.letters) |*l| {
            l.x -= SPEED;
            if (l.x > -FONT_W) continue;
            l.x = WIDE * FONT_W + (l.x + FONT_W);
            l.char = t.text[self.scroffset];
            self.scroffset += 1;
            if (self.scroffset > t.text.len - 1) self.scroffset = 0;
        }
    }

    fn drawPicture(self: *Demo, fb: *LogicalFB, view: blit.Dst) void {
        const fill = if (self.picture == .midearth) MIDEARTH_FILL else BLACK;
        fb.setPaletteEntry(FILL, rgb(fill));
        fillRows(view, 0, SCROLL_Y, FILL); // rows below are the band's and the bottom's
        const pic = self.picture orelse return;
        const a = fadeAlpha(self.pic_n);
        const raw: []const u8 = if (pic == .einhorn) self.einhorn(fb, a) else blk: {
            const s = single(pic);
            for (s.pal, 0..) |c, k| fb.setPaletteEntry(PIC_BASE + @as(u8, @intCast(k)), rgb(over(c, fill, a)));
            break :blk s.raw;
        };
        blit.blit(view, blit.Image.init(raw, PIC_W), null, PIC_X - CROP_X, PIC_Y, null, .{ .offset = PIC_BASE });
        if (pic != .midearth) return;
        const cycle = jsRound(self.pic_n, SHIMMER_STEP) % SHIMMER_FRAMES;
        const part = blit.Rect{ .x = 0, .y = SHIMMER_H * cycle, .w = SHIMMER_W, .h = SHIMMER_H };
        blit.blit(view, shimmer_img, part, SHIMMER_X - CROP_X, SHIMMER_Y, 0, .{ .offset = SHIMMER_OFFSET });
    }

    /// display_einhorn: stars, then the unicorn, both at alpha a over black.
    fn einhorn(self: *Demo, fb: *LogicalFB, a: f32) []const u8 {
        const star = jsRound(self.pic_n, STAR_STEP) % STAR_FRAMES;
        if (self.einhorn_star != star) {
            @memcpy(&einhorn_canvas, einhorn_raw);
            for (t.star_frames[star]) |s| einhorn_canvas[s.at] += s.colour;
            self.einhorn_star = star;
        }
        for (t.einhorn_pal, 0..) |ink, e| for (t.star_pal, 0..) |sc, s| {
            const under = over(sc, BLACK, a);
            const c = if (e == 0) under else over(ink, under, a);
            fb.setPaletteEntry(PIC_BASE + @as(u8, @intCast(e * STAR_COLOURS + s)), rgb(c));
        };
        return &einhorn_canvas;
    }

    fn drawScroller(self: *Demo, view: blit.Dst) void {
        // quad(0, 231, screen_width, 16): the band is colour 0 edge to edge,
        // which is why the border carries it on a screen with closed sides.
        fillRows(view, SCROLL_Y, SCROLL_H, BORDER_REG);
        const box = view.window(SCROLL_X - CROP_X, SCROLL_Y, SCROLL_W, SCROLL_H);
        // The twelve raster lines: screen width only, a non-zero register.
        fillRows(box, GRAD_TOP, 2 * GRAD_SLICE, GRAD_INK);
        for (self.letters) |l| {
            const nb: usize = l.char - FONT_FIRST;
            const tile = blit.Rect{ .x = nb % FONT_COLS * FONT_W, .y = nb / FONT_COLS * FONT_H, .w = FONT_W, .h = FONT_H };
            blit.blit(box, font_img, tile, l.x, 0, 0, .{ .offset = FONT_OFFSET });
        }
    }
};
