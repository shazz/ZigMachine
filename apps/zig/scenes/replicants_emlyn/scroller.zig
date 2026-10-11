// --------------------------------------------------------------------------
// The scrolltext: CODEF scrolltext_horizontal (codef_scrolltext.js), set up as
//
//   myfont.initTile(64, 64, 32)
//   myscrolltext.init(mycanvas, myfont, 4)      screen.js:74-77
//   myscrolltext.draw(390)                      screen.js:102
//
// init() is called with NO sinparam, so the draw loop's `prov` stays 0 for
// every letter: THIS SCROLLER IS FLAT. The sort by posx only fixes draw order
// between non-overlapping tiles, so it changes nothing and is not kept.
//
// wide = ceil(640 / 64) + 1 = 11, and the ring loops `i <= wide`, so the
// remake has TWELVE letters. Letter i starts at canvas x 11*64 + i*64, moves 4
// canvas pixels a frame, and on reaching -64 rejoins at 704 + (posx + 64)
// carrying the next character. Every x is even, so halving is exact.
//
// That ring is sized to the 640-px CANVAS, and this port draws to the 400-px
// raster, so it is widened here (and only the ring: text, speed, spacing and
// start are the remake's). Canvas -64 is plane column 8, so the remake's ring
// recycled every letter while all 32 of its columns were still showing in the
// opened left border — letters were cut off there instead of scrolling out,
// while on the right they came in off the raster. Now a letter leaves only
// once its right edge has passed plane column 0 (canvas -144) and rejoins
// beyond column 400. Every letter slot sees the same x and the same character
// on the same frame as in the remake; the ring just keeps two more of them.
//
// drawTile's y is the tile TOP (drawPart translates by -handle, and the font is
// not mid-handled), so canvas y 390 is ST row 195 and the band is rows 195..226.
//
// It draws to the WHOLE 400x280 raster, not the canvas window: with the rasters
// and the logo both running edge to edge, the scrolltext was the only thing
// still stopping at an edge this screen no longer has. Plane column X is
// content x + CONTENT_X and plane row Y is content y + CONTENT_Y — the same
// mapping rasters.zig uses for the ramp and logo.zig for the logo.
//
// ZIG MODE bends it on CODEF 484's middle scroller, the curve picked out of the
// distortion lab: cascade-archeology.js:76-79, amp HALVED and inc DOUBLED for
// ST, offset per frame unchanged. The filter is codef_fx.siny with 1-px
// columns, i.e. libs/zig/effects/wave.zig's siny, drawn here by bent() with the
// same pixels in row order (the board's cart CPU paid for siny's call per
// column); the curve it is fed is curve.zig's, in the cart's numbers. The phase is a function of the SCREEN column (CODEF's
// `.multiply` form, value + inc*x) because the glyphs are blitted one at a
// time, not walked as one strip.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const Rect = @import("dirty.zig").Rect;
const REACH = @import("curve.zig").REACH;

/// screen.js:76, exactly. Its authors' words, not ours.
pub const TEXT = "abcdefghij      THE FUCKING BEST REPLICANTS ST AMIGOS PRESENTS:- EMLYN HUGUES FOOTBALL - BROKEN BY THE REPLICANTS     ONLY A FEW FUCKINGS TO NOCKTANAL THE CANADIANS DICKHEAD, OVERWANKERS DAY AFTER DAY YEAR AFTER YEAR YOU ARE LAMEST AND LAMEST JUST SOME GREETINGS TO OUR BEST FRIENDS: MCA, AUTOMATION, HOTLINE, TCB, TEX, DEREK MD...  CREDITS FOR THIS SCREEN                    CODING -VICKERS-                    AMIGAFONT RIPPER -VANTAGE- FROM ST CONNEXION                    BIG REPLICANTS LOGO BY -PULSAR- FROM NEXT                    MUSIX -MAD MAX- FROM -T-          END OF SCROLL       ";

const FIRST_CHAR = 32; // initTile's tilestart
const TILE_C = 64; // initTile(64, 64): canvas pixels
const TILE = TILE_C / 2; // ST pixels
const COLS = A.FONT_W / TILE; // img.width / tilew = 10
const TILES = COLS * (A.FONT_H / TILE); // 80: characters 32..111
const SPEED = 4; // init(..., 4)
const WIDE = 11; // Math.ceil(640 / 64) + 1
const START_C = WIDE * TILE_C; // 704: the ring loops i = 0 to wide INCLUSIVE
pub const ROW = 390 / 2 + @as(i32, @intCast(A.CONTENT_Y)); // draw(390) halved, on the raster
const ORIGIN_X: i32 = @intCast(A.CONTENT_X);
const RASTER_W: i32 = @intCast(A.CONTENT_W + 2 * A.CONTENT_X); // 400, the whole plane row
const RASTER_H: i32 = @intCast(A.CONTENT_H + 2 * A.CONTENT_Y); // 280

/// Canvas x at which a letter's right edge reaches plane column 0: -144, not
/// the remake's -64 (which is plane column 8, still inside the left border).
const EXIT_C: i32 = -2 * (ORIGIN_X + TILE);
/// Enough letters that the one rejoining lands past the raster's right edge.
pub const LETTERS: usize = @intCast(@divFloor(RASTER_W + TILE + TILE - 1, TILE)); // 14
const RING_C: i32 = @intCast(LETTERS * TILE_C); // 896

comptime {
    // A rejoining letter must start wholly off the right edge, or it pops in.
    if (@divExact(EXIT_C + RING_C, 2) + ORIGIN_X < RASTER_W) @compileError("scroller ring too short for the raster");
    // Every x is START_C - SPEED*n + k*TILE_C: EXIT_C must be one of them, so
    // a letter leaves on the exact frame it is fully off, never a step late.
    if (@mod(START_C - EXIT_C, SPEED) != 0) @compileError("EXIT_C is not on the scroll's step");
}

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + TILES) @compileError("scrolltext character outside font.png");
}

/// Every pixel draw() can touch, the whole raster wide: the tile's own rows
/// when flat, and the curve's reach above and below them when bent.
pub fn band(flat: bool) Rect {
    const m: i32 = if (flat) 0 else REACH;
    return .{ .x0 = 0, .y0 = @max(0, ROW - m), .x1 = RASTER_W, .y1 = @min(RASTER_H, ROW + TILE + m) };
}

/// `Curve` is the cart's: curve.zig's CurveFixed or CurveF32 (with the Mode
/// its sweep() reads the bend from).
pub fn Scroller(comptime Curve: type, comptime Mode: type) type {
    return struct {
        const Self = @This();
        posx: [LETTERS]i32, // canvas pixels, always even
        ltr: [LETTERS]u8,
        offset: usize, // scroffset
        curve: Curve, // 484's `value`, advanced a frame

        pub fn init(self: *Self) void {
            self.offset = 0;
            self.curve.init();
            for (&self.posx, &self.ltr, 0..) |*x, *c, i| {
                x.* = @intCast(START_C + i * TILE_C);
                c.* = TEXT[self.offset];
                self.offset += 1;
            }
        }

        /// The first half of draw(): every letter moves, and one that has left
        /// the canvas rejoins the back of the ring with the next character.
        pub fn update(self: *Self) void {
            self.curve.step();
            for (&self.posx, &self.ltr) |*x, *c| {
                x.* -= SPEED;
                if (x.* > EXIT_C) continue;
                x.* += RING_C;
                c.* = TEXT[self.offset];
                self.offset += 1;
                if (self.offset > TEXT.len - 1) self.offset = 0;
            }
        }

        /// A flat mode (ORIGINAL, bend 0) draws the original's own plain blit,
        /// not a flat sweep, so the frame is the faithful port's. Bent, the
        /// letters ride 484's curve scaled by the bend, so switching modes grows
        /// and flattens the bend instead of snapping it.
        pub fn draw(self: *const Self, dst: blit.Dst, font: blit.Image, mode: *const Mode) void {
            for (self.posx, self.ltr) |x, c| {
                const g: usize = c - FIRST_CHAR;
                const cell = blit.Rect{ .x = g % COLS * TILE, .y = g / COLS * TILE, .w = TILE, .h = TILE };
                const dx = @divExact(x, 2) + ORIGIN_X;
                if (mode.flat()) {
                    blit.blit(dst, font, cell, dx, ROW, A.TRANSPARENT, .copy);
                    continue;
                }
                var it = self.curve.sweep(mode, dx);
                bent(dst, font, cell, dx, &it);
            }
        }
    };
}

/// wave.siny(dst, font, cell, dx, ROW, 1, sweep, TRANSPARENT, .copy), pixel for
/// pixel, walked ROW by row instead of column by column: siny makes one
/// clipped blit per 1-px column (448 calls a frame, each a clip and a switch
/// for 32 pixels), where this takes the 32 column offsets first (consuming
/// the sweep exactly as siny does, drawn or not) and then reads each glyph row
/// once, left to right. Every column writes its own x, so the order the
/// pixels go down in changes nothing.
fn bent(dst: blit.Dst, font: blit.Image, cell: blit.Rect, dx: i32, sweep: anytype) void {
    var top: [TILE]i32 = undefined; // the plane row of each column's first pixel
    for (&top) |*t| t.* = ROW + sweep.next();
    const w: i32 = @intCast(dst.w);
    const h: i32 = @intCast(dst.h);
    const c0: usize = @intCast(@min(TILE, @max(0, -dx))); // the columns on the plane
    const c1: usize = @intCast(@max(0, @min(TILE, w - dx)));
    if (c0 >= c1) return;
    for (0..TILE) |r| {
        const in = font.data[(cell.y + r) * font.w + cell.x ..][0..TILE];
        for (c0..c1) |c| {
            const p = in[c];
            if (p == A.TRANSPARENT) continue;
            const y = top[c] + @as(i32, @intCast(r));
            if (y < 0 or y >= h) continue;
            dst.buf[@as(usize, @intCast(y)) * dst.stride + @as(usize, @intCast(dx + @as(i32, @intCast(c))))] = p;
        }
    }
}
