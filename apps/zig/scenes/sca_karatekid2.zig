// --------------------------------------------------------------------------
// SCA - THE KARATE KID PART II — the Swiss Cracking Association's crack intro,
// Amiga, July 1987 (cracked for Big Apple). The scroll text is theirs, byte for
// byte; the remake, its framework and the artwork credit Christian Murtas /
// Codef. Ported from prototypes/codef/495/screen.js, read against lib/
// codef_core.js, codef_scrolltext.js and codef_starfield.js.
//
// MEASURED GEOMETRY (the canvas is 640x480 = 320x240 doubled, halved here):
//   stars         rows 0..239, all of them (the starfield wraps the full canvas)
//   raster bar    rows 50..77  (28 rows: raster.png's row pairs are identical)
//   scroller      rows 60..66  (fontraster is 14 canvas rows = 7 ST rows)
//   logo          x 82..231, rows 120..191 (150x72, grid (0,0) exact)
// Stars reach row 239, so the content is 320x240: the ST's 200 visible rows
// plus a 40-row bottom border, opened the way automation442/elite_cfsr open
// theirs. The plane is one 400x280 overscan buffer; content (0,0) is physical
// (40,40), so the bottom border carries rows 200..239 and the top border is
// black. Borders open with the copper's flicker, every line.
//
// WHAT IS ON SCREEN, AND HOW IT IS DONE
//   stars       four layers of 40 one-pixel stars (CODEF: 2x2 canvas dots).
//               Speeds 3.5/2/1/0 canvas px a frame = 1.75/1/0.5/0 px: quarter-
//               pixel integers (7/4/2/0). Each star's old pixel is erased and
//               its new one drawn, in CODEF's layer order (later layers win).
//               Stars under the bar are hidden by it, so they are never drawn;
//               stars behind the logo are hidden by its opaque pixels.
//   raster bar  the BACKDROP register (palette index 0) rewritten per line by
//               zg.copper. Rows outside the bar are black, rows of the bar are
//               raster.png's 28 colours, and the border shows the same register
//               (it is the same line), so the bar runs edge to edge.
//   scroller    CODEF's scrolltext_horizontal letter ring (zg.scrollring, in
//               canvas units: 38 letters, 18 apart, speed 3). Drawn at half
//               resolution: letter x in canvas px halves to the screen column
//               (x >> 1), so the 1.5 px a frame is a 1 then 2 px step. The band
//               is shifted, not redrawn: each frame memmoves the seven rows by
//               that step and draws only the newly exposed columns.
//   ink         the font's ink index rewritten per line by zg.copper, which
//               reproduces fontraster's source-in gradient. The glyph's eighth
//               row is dropped: fontraster is only 14 canvas rows, so source-in
//               leaves glyph rows 14..15 transparent.
//   logo        static: written once in init(). Nothing in CODEF moves it.
//               angleLogoDef (screen.js:130) is declared and never read, so no
//               tilt is ported.
//
// PALETTE: every channel of raster.png, fontraster.png, the star colours and the
// logo is a multiple of 17 (Amiga 12-bit), so the colours are kept exactly.
//
// MUSIC: no music. The original 1987 SCA intro is silent (per the SCA website);
// the CODEF remake's music.play() is commented out and loads nothing.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const LOGO = @embedFile("../assets/screens/sca_karatekid2/logo.raw");
const FONT = @embedFile("../assets/screens/sca_karatekid2/font1x.raw");

const TEXT = "                          IT IS DONE !                      THE MEGA-MIGHTY SWISS CRACKING ASSOCIATION IN COOPERATION WITH BIG APPLE PRESENT:  KARATE KID II*    CRACKED IN JULY 1987.      A BIG HELLO TO   ACS - CHRIS - D.S. COMPWARE - DANISH GOLD - DYNAMIC DUO - ECA - HOTLINE - IRATA - KGB - SSI - SUPREMACY - THE MOVERS  AND ALL OUR OTHER CONTACTS ALL OVER THE WORLD ...     WATCH OUT FOR OUR OTHER GREAT PRODUCTIONS LIKE  SCATOM & ROMCRACK ...         PRESS THE LEFT MOUSE BUTTON TO GO ON !!   REMAKE BY CHRISTIAN MURTAS WITH CODEF FRAMEWORK                                ";

const PLANE = 0;
const PHYS_W: u16 = zg.PHYSICAL_WIDTH;
const PHYS_H: u16 = zg.PHYSICAL_HEIGHT;
const ORIGIN_X: u16 = 40; // the content's (0,0) in the physical buffer
const ORIGIN_Y: u16 = 40;
const SCREEN_W: u16 = 320;
const SCREEN_H: u16 = 240;

// Palette indices. 0 and 1 are copper slots (the bar and the ink, per line).
const IDX_BACK: u8 = 0;
const IDX_INK: u8 = 1;
const IDX_STAR0: u8 = 2; // stars: layers 0..3 are indices 2..5
const IDX_LOGO0: u8 = 16; // logo: its PNG indices 1..14 are 16..29; 0 is transparent

const STAR_RGB = [4][3]u8{ .{ 221, 238, 238 }, .{ 136, 170, 187 }, .{ 85, 102, 136 }, .{ 34, 68, 85 } };
// Quarter-pixel speeds: CODEF's 3.5, 2, 1, 0 canvas px a frame, halved to screen px.
const LAYER_SPEED_Q = [4]u16{ 7, 4, 2, 0 };
const STARS_PER_LAYER = 40;
const NSTARS = 4 * STARS_PER_LAYER;
const STAR_NONE: u16 = 0xFFFF;
const SCREEN_W_Q: u16 = SCREEN_W * 4; // CODEF wraps at canvas width 640 = 1280 quarter px

const BAR_Y = 50;
const BAR_RGB = [28][3]u8{
    .{ 0, 255, 255 }, .{ 0, 238, 255 }, .{ 0, 204, 255 }, .{ 0, 170, 255 },
    .{ 0, 136, 255 }, .{ 0, 102, 255 }, .{ 0, 0, 204 },   .{ 34, 17, 102 },
    .{ 34, 17, 102 }, .{ 34, 17, 102 }, .{ 34, 17, 102 }, .{ 34, 17, 102 },
    .{ 34, 17, 102 }, .{ 34, 17, 102 }, .{ 34, 17, 102 }, .{ 34, 17, 102 },
    .{ 34, 17, 102 }, .{ 34, 17, 102 }, .{ 34, 17, 102 }, .{ 34, 17, 102 },
    .{ 0, 102, 255 }, .{ 0, 51, 238 },  .{ 0, 34, 204 },  .{ 0, 34, 170 },
    .{ 0, 17, 136 },  .{ 0, 17, 102 },  .{ 0, 17, 68 },   .{ 0, 0, 34 },
};

const TEXT_Y = 60;
const TEXT_ROWS = 7;
const INK_RGB = [7][3]u8{
    .{ 255, 221, 187 }, .{ 255, 204, 170 }, .{ 238, 187, 153 }, .{ 238, 170, 136 },
    .{ 204, 153, 119 }, .{ 204, 136, 102 }, .{ 187, 119, 85 },
};

const LOGO_X = 82;
const LOGO_Y = 120;
const LOGO_W = 150;
const LOGO_H = 72;
// logo.png's own palette, PNG index 1..14 (index 0 is transparent).
const LOGO_RGB = [14][3]u8{
    .{ 153, 153, 204 }, .{ 187, 187, 221 }, .{ 85, 85, 136 },  .{ 170, 136, 153 },
    .{ 136, 102, 119 }, .{ 204, 170, 187 }, .{ 119, 119, 170 }, .{ 102, 68, 85 },
    .{ 238, 238, 255 }, .{ 255, 255, 255 }, .{ 68, 34, 51 },   .{ 238, 204, 221 },
    .{ 51, 51, 119 },   .{ 34, 34, 85 },
};

// fontraster rows 0..13 are the glyph rows; the glyph is 9x7 at screen res.
const GLYPH_W = 9;
const GLYPH_ROWS = TEXT_ROWS;
const GLYPH_FIRST = 32;
const LETTERS = 38; // CODEF: wide = ceil(640/18)+1 = 37, letters 0..37
const GLYPH_CANVAS: i32 = 18;
const RING_START: i32 = 666; // CODEF: wide * fontw
const SCROLL_SPEED: i32 = 3;

const Star = struct {
    x: u16, // quarter screen pixels, 0..1279
    y: u16, // screen row, fixed: CODEF's starfield has no vertical speed
    prev: u16, // pixel column drawn last frame, STAR_NONE if none
    layer: u8,
};

pub const Demo = struct {
    ok: bool,
    stars: [NSTARS]Star,
    ring: zg.scrollring.Ring(i32, LETTERS),
    base: i32, // canvas px the ring has moved, for the half-res shift

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        initScene(self, zigos);
    }

    // Nothing advances outside the frame: CODEF moves its stars and letters
    // inside go1(), which is the render.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        renderScene(self, zigos, dt);
    }
};

// The copper's two slots, one table per PHYSICAL row (the scene owns them).
var copper_tables: [2]zg.copper.Table = undefined;

fn initScene(self: *Demo, zigos: *ZigOS) void {
    const fb = &zigos.lfbs[PLANE];
    fb.is_enabled = true;
    fb.setPalette(buildPalette());
    fb.setOverscanBuffer();
    zg.copper.install(fb, &.{ IDX_BACK, IDX_INK }, &copper_tables, .{ .flicker = true });
    buildCopper(fb);
    zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    fb.clearFrameBuffer(IDX_BACK);
    drawLogo(fb);

    self.stars = initStars();
    self.ring = zg.scrollring.Ring(i32, LETTERS).init(TEXT, RING_START, GLYPH_CANVAS);
    self.base = 0;
    self.ok = true;
}

// CODEF's render order: the starfield (draw, then move), then the scroller
// (move, then draw), then the bar, the text and the logo, which are static.
fn renderScene(self: *Demo, zigos: *ZigOS, dt: f32) void {
    _ = dt;
    if (!self.ok) return;
    const fb = &zigos.lfbs[PLANE];
    drawStars(fb, &self.stars);
    moveStars(&self.stars);
    scrollBand(fb, self);
}

// --------------------------------------------------------------------------
// Palette, copper, logo
// --------------------------------------------------------------------------

fn rgb(c: [3]u8) Color {
    return Color{ .r = c[0], .g = c[1], .b = c[2], .a = 255 };
}

fn buildPalette() [256]Color {
    var p: [256]Color = [_]Color{rgb(.{ 0, 0, 0 })} ** 256;
    for (STAR_RGB, 0..) |c, layer| p[IDX_STAR0 + layer] = rgb(c);
    for (LOGO_RGB, 0..) |c, j| p[IDX_LOGO0 + j] = rgb(c);
    return p;
}

// Physical row r is content row r - ORIGIN_Y. Rows above and below the content
// are black; the bar and the ink exist only on their own rows.
fn buildCopper(fb: *const zg.LogicalFB) void {
    const back = zg.copper.table(fb, IDX_BACK);
    const ink = zg.copper.table(fb, IDX_INK);
    for (0..PHYS_H) |row| {
        const cy: i32 = @as(i32, @intCast(row)) - ORIGIN_Y;
        back[row] = copperColour(cy - BAR_Y, &BAR_RGB);
        ink[row] = copperColour(cy - TEXT_Y, &INK_RGB);
    }
}

// The colour of line `i` of a band (i counts from the band's first row), black
// outside it.
fn copperColour(i: i32, band: []const [3]u8) u32 {
    if (i < 0 or i >= band.len) return rgb(.{ 0, 0, 0 }).toRGBA();
    return rgb(band[@intCast(i)]).toRGBA();
}

fn drawLogo(fb: *zg.LogicalFB) void {
    for (0..LOGO_H) |y| {
        for (0..LOGO_W) |x| {
            const v = LOGO[y * LOGO_W + x];
            if (v != 0) put(fb, LOGO_X + @as(u16, @intCast(x)), LOGO_Y + @as(u16, @intCast(y)), v);
        }
    }
}

// The logo's own opaque pixel at a content position, 0 where it is transparent.
fn logoAt(x: u16, y: u16) u8 {
    if (x < LOGO_X or x >= LOGO_X + LOGO_W) return 0;
    if (y < LOGO_Y or y >= LOGO_Y + LOGO_H) return 0;
    return LOGO[(y - LOGO_Y) * LOGO_W + (x - LOGO_X)];
}

// Content coordinates to the physical buffer.
fn put(fb: *zg.LogicalFB, x: u16, y: u16, v: u8) void {
    fb.setPixelValue(ORIGIN_X + x, ORIGIN_Y + y, v);
}

// --------------------------------------------------------------------------
// Stars
// --------------------------------------------------------------------------

fn initStars() [NSTARS]Star {
    var out: [NSTARS]Star = undefined;
    var rng: u32 = 0x1987_0495; // fixed seed: CODEF's Math.random has no table to copy
    for (&out, 0..) |*s, i| {
        const layer: u8 = @intCast(i / STARS_PER_LAYER);
        s.* = .{
            .x = nextBelow(&rng, SCREEN_W_Q),
            .y = nextBelow(&rng, SCREEN_H),
            .prev = STAR_NONE,
            .layer = layer,
        };
    }
    return out;
}

fn nextBelow(rng: *u32, n: u16) u16 {
    rng.* = rng.* *% 1664525 +% 1013904223;
    return @intCast((rng.* >> 8) % n);
}

// A star is hidden where the bar (opaque, drawn after the stars in CODEF) or
// the logo's opaque pixels cover it; it is then never drawn at all.
fn starVisible(x: u16, y: u16) bool {
    if (x >= SCREEN_W) return false;
    if (y >= BAR_Y and y < BAR_Y + BAR_RGB.len) return false;
    return logoAt(x, y) == 0;
}

// Erase every star's last pixel, then draw all of them in layer order, so the
// last layer drawn wins, as in CODEF. Only pixels that moved are rewritten by
// the erase/draw pair; a star that did not move gets its own pixel back.
fn drawStars(fb: *zg.LogicalFB, stars: *[NSTARS]Star) void {
    for (stars) |*s| {
        if (s.prev == STAR_NONE) continue;
        put(fb, s.prev, s.y, 0);
    }
    for (stars) |*s| {
        const px: u16 = s.x >> 2;
        if (!starVisible(px, s.y)) {
            s.prev = STAR_NONE;
            continue;
        }
        put(fb, px, s.y, IDX_STAR0 + s.layer);
        s.prev = px;
    }
}

// CODEF: x += speedx, and x > width wraps to 0 (no wrap to the left: speeds are >= 0).
fn moveStars(stars: *[NSTARS]Star) void {
    for (stars) |*s| {
        s.x += LAYER_SPEED_Q[s.layer];
        if (s.x > SCREEN_W_Q) s.x = 0;
    }
}

// --------------------------------------------------------------------------
// Scroller band
// --------------------------------------------------------------------------

// The ring is in canvas px; letter x halves to the screen column. Every letter
// moves by the same amount, so the band is shifted by that step (1 or 2 px) and
// only the exposed right-hand columns are drawn.
fn scrollBand(fb: *zg.LogicalFB, self: *Demo) void {
    const old = self.base;
    self.base += SCROLL_SPEED;
    _ = self.ring.step(SCROLL_SPEED);
    const shift: u16 = @intCast(ceilHalf(self.base) - ceilHalf(old));
    for (0..TEXT_ROWS) |r| shiftRow(fb, @intCast(r), shift);
    for (0..LETTERS) |i| drawLetterColumns(fb, self.ring.x[i], self.ring.c[i], shift);
}

fn ceilHalf(v: i32) i32 {
    return (v + 1) >> 1;
}

fn bandRow(fb: *zg.LogicalFB, r: u16) []u8 {
    const at: usize = (@as(usize, ORIGIN_Y) + TEXT_Y + r) * PHYS_W + ORIGIN_X;
    return fb.fb[at..][0..SCREEN_W];
}

// Move one band row left by `shift`, then clear the columns it exposes.
fn shiftRow(fb: *zg.LogicalFB, r: u16, shift: u16) void {
    const row = bandRow(fb, r);
    std.mem.copyForwards(u8, row[0 .. SCREEN_W - shift], row[shift..SCREEN_W]);
    @memset(row[SCREEN_W - shift ..], IDX_BACK);
}

// The glyph's columns that land in the exposed strip. A letter at canvas x
// starts at screen column x >> 1, and its 9 art columns are 9 screen columns.
fn drawLetterColumns(fb: *zg.LogicalFB, x: i32, ch: u8, shift: u16) void {
    if (ch < GLYPH_FIRST or ch - GLYPH_FIRST >= FONT.len / (GLYPH_W * GLYPH_ROWS)) return;
    const glyph: usize = ch - GLYPH_FIRST;
    const left: i32 = x >> 1; // arithmetic: floor(x / 2)
    const exposed_from: i32 = SCREEN_W - shift;
    for (0..GLYPH_W) |k| {
        const col: i32 = left + @as(i32, @intCast(k));
        if (col < exposed_from or col >= SCREEN_W) continue;
        for (0..GLYPH_ROWS) |r| {
            if (FONT[(glyph * GLYPH_ROWS + r) * GLYPH_W + k] != 0)
                put(fb, @intCast(col), TEXT_Y + @as(u16, @intCast(r)), IDX_INK);
        }
    }
}
