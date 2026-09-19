// --------------------------------------------------------------------------
// THE CAREBEARS — COLORSHOCK 2, from The Cuddly Demos.
//   original: code TCB, music MAD MAX (Jochen Hippel)
//   CODEF HTML5 remake (screen 172) by AYOROS / Impact, MIT-licensed
//
// Ported from prototypes/codef/172/screen.js. What is on screen: the bouncing
// all-512-colours square field, the THE CAREBEARS logo, and one scrolltext in a
// strip that rides up and down a 1873-entry table. That is the whole screen.
//
// GEOMETRY. mycanvas is 680x400 = an ST 340x200 doubled, NOT 320x200 — every
// coordinate below is the original's halved, and the 20 extra columns are real:
// this is a TCB screen, so they are the SIDE BORDERS. The port therefore runs on
// the 400x280 OVERSCAN plane and maps the remake's 340x200 canvas onto it at
// (30, 40): canvas x 0..339 -> logical x -10..329 (10 px into each side border),
// canvas y 0..199 -> the visible band exactly. The remaining border rows are
// filled by extending the background pan, which costs nothing (see below).
//
// DELIBERATE DEPARTURES FROM THE REMAKE:
//  1. The fake AtariDecrunch depack intro (screen.js init()/init2()) is NOT
//     ported: ZigMachine has that look as a REAL depack effect (zx0.Fx.automation).
//  2. The background is not re-blitted per frame. go() redraws the whole
//     2492x1152 sheet every frame at a Lissajous position; we paint ONE pan
//     buffer at init and move the READ POINTER with setScroll() — one register
//     write, zero pixels.
//  3. mycanvas_anim (600x400) is created, drawn to mycanvas every frame and
//     never painted: a dead offscreen. Dropped.
//  4. The 512 colours are done the way TCB did them — a PALETTE PER SCANLINE
//     (see the HBL below) — instead of quantizing the field into 256 entries,
//     which measured a mean error of 15/255 on a picture whose whole point is
//     its colours.
//
// Everything else is the original's own numbers: the vbl increment of 0.8, the
// sin/cos amplitudes, the movescroll table lifted verbatim out of screen.js, the
// scrolltext slot arithmetic of lib/codef_scrolltext.js.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

// --------------------------------------------------------------------------
// Assets (tools/private_tools/tcb_colorshock_assets.py)
// --------------------------------------------------------------------------
const fond_b = @embedFile("../assets/screens/tcb_colorshock/fond.raw");
const fond_rows = @embedFile("../assets/screens/tcb_colorshock/fond_rows.pal");
const font_b = @embedFile("../assets/screens/tcb_colorshock/font.raw");
const logo_b = @embedFile("../assets/screens/tcb_colorshock/logo.raw");
const acc_b = @embedFile("../assets/screens/tcb_colorshock/acc.raw");
const ink_pal = convertU8ArraytoColors(@embedFile("../assets/screens/tcb_colorshock/ink_pal.dat"));
const movescroll_b = @embedFile("../assets/screens/tcb_colorshock/movescroll.dat");

// MUSIC. The remake plays Colorshock.ym, a register dump — deprecated here. The
// dump's own YM6 header names the tune "Cuddly Demos: Coloshock" by Jochen
// Hippel, and no SNDH carries that title; the match was found by playing every
// tune in Mad_Max/Demos/Cuddly_Demos/ and comparing register streams. Comic
// Bakery is IDENTICAL: registers 0..12 agree with the dump on all 9600 frames
// (r13 differs only because the dump writes $ff for "envelope not retriggered").
// So Colorshock's music is the Cuddly Demos' Comic Bakery tune. FLAG ~y, one
// subtune, peak 0.33 through apps/sndh_headless.mjs.
const MUSIC = "comic_bakery.sndh";

// --------------------------------------------------------------------------
// Background: a Lissajous pan over an overscan scroll plane
// --------------------------------------------------------------------------
// screen.js: myfond.setmidhandle() then, every frame,
//   myfond.draw(fond, 400 - sin(vbl*PI/100)*400, 180 - cos(vbl*PI/200)*300)
// setmidhandle() makes that the CENTRE, so the sheet's top-left lands at
// (X-623, Y-288) in ST pixels, with X = 200 - sin(vbl*PI/100)*200 in [0,400] and
// Y = 90 - cos(vbl*PI/200)*150 in [-60,240].
//
// Plane pixel (px,py) is canvas pixel (px-30, py-40), so it samples the sheet at
//   src_x = px + 593 - X,  src_y = py + 248 - Y.
// Over px in 0..399 and py in 0..279 that is src_x in [193,992] — 800 columns —
// and src_y in [8,587].
//
// The sheet is 1246x576 at ST scale and VERTICALLY PERIODIC with period 288 (row
// y and row y+288 are bit-identical), so src_y is taken mod 288 and only the
// 288-row tile is stored. The pan buffer is that tile repeated to 568 rows.
//
// VRAM. 800*568 = 454400 B here, plus the ink plane's 112000 B, plus the four
// 64000 B planes the machine allocates at boot and never reclaims = 822400 B of
// the 1 MiB pool. vramAlloc() has no pool guard, so the bound is checked at
// comptime below rather than trusted.
const TILE_W: u16 = 800;
const TILE_H: u32 = 288;
const BUF_W: u16 = TILE_W;
const BUF_H: u16 = zg.PHYSICAL_HEIGHT + @as(u16, TILE_H); // 568
const ROW_COLOURS: usize = 105; // the widest scanline of the pan window
const ROW_PAL_BYTES: usize = ROW_COLOURS * 4;

// Where the canvas sits on the 400x280 plane.
const OX: i32 = 30;
const OY: u16 = 40;

comptime {
    // The pan never leaves the buffer: scroll x is round(200+sin*200) clamped to
    // 0..400 and scroll y is a value mod 288, so the last byte the machine can
    // read is (287+279)*800 + (400+399) = 453599, inside 454400.
    if (TILE_H - 1 + zg.PHYSICAL_HEIGHT > BUF_H) @compileError("pan buffer too short");
    if (400 + zg.PHYSICAL_WIDTH > BUF_W) @compileError("pan buffer too narrow");
    if (fond_b.len != @as(usize, TILE_W) * TILE_H) @compileError("fond.raw is not one TILE_W x TILE_H tile");
    if (fond_rows.len != @as(usize, TILE_H) * ROW_PAL_BYTES) @compileError("fond_rows.pal is not TILE_H rows of ROW_COLOURS");
    // The four NORMAL planes ZigOS allocates at boot are never reclaimed, so the
    // pan buffer and the ink plane are allocated ON TOP of them.
    const VRAM = zg.NB_PLANES * zg.NORMAL_FB_BYTES + @as(usize, BUF_W) * BUF_H + zg.OVERSCAN_FB_BYTES;
    if (VRAM > zg.VRAM_BYTES) @compileError("over the VRAM pool");
}

// The tile row shown on physical line 0 — the scroll offset AND the palette
// offset, which are the same number by construction.
var pan_row: u32 = 0;

// One palette per scanline: the ST trick this screen is named for. An HBL that
// also opens the borders, so it replaces flickerAllHbl rather than fighting it.
// (zg.copper drives 4 entries a line and zg.linepal allocates them per frame;
// this table is static and 105 wide, so a plain memcpy is both.)
fn panHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    const row: usize = (pan_row + line) % TILE_H;
    const src = fond_rows[row * ROW_PAL_BYTES ..][0..ROW_PAL_BYTES];
    const dst = @as([*]u8, @ptrCast(fb.palette))[0..ROW_PAL_BYTES];
    @memcpy(dst, src);
}

// --------------------------------------------------------------------------
// The scroll strip (mycanvas_scroll, 600x500 = ST 300x250)
// --------------------------------------------------------------------------
// Only its top 26 rows ever hold anything: the glyphs are drawn at y=0 and
// scroll_acc.png is drawn over them at (0,0). The strip is blitted to the screen
// at (40, movescroll[pos_scroll]) => ST (20, movescroll/2), so it is composited
// here straight onto the ink plane at (OX+20, OY+movescroll/2).
const STRIP_X: i32 = OX + 20; // 50
const STRIP_XU: usize = @intCast(STRIP_X);
const STRIP_W: i32 = 300;
const STRIP_WU: usize = @intCast(STRIP_W);
const STRIP_H: u16 = 26;

// lib/codef_scrolltext.js: wide = ceil(dst_w/fontw)+1 and the loops run i<=wide.
// The destination is the strip, the original's own 600-wide canvas halved, so
// the arithmetic halves exactly: ceil(600/70)+1 = ceil(300/35)+1 = 10.
const GLYPH_W: i32 = 35;
const GLYPH_H: u16 = 26;
const FONT_SHEET_W: usize = 350;
const GLYPH_COLS: usize = 10;
const FIRST_CHAR: u8 = 32; // myfont.initTile(70,52,32)
const LAST_CHAR: u8 = 91;
const WIDE: i32 = 10;
const NB_SLOTS: usize = 11;
const SCROLL_START: i32 = WIDE * GLYPH_W; // 350
const SCROLL_SPEED: i32 = 3; // 6 in CODEF

const SCROLL_TEXT = "        HELLO!  THIS IS THE COLORSHOCK DEMO!  CODING BY THE CAREBEARS AND MUSAXX BY MAD MAX.  EVERY ONE OF THOSE SQUARES BOUNCING BEHIND THIS SCROLLER CONTAINS ALL 512 POSSIBLE COLOURS, IMPRESSIVE? NO?  NO, NOT EXTREMELY. THIS IS A )DISK-FILLER)-DEMO. AT THE TIME OF WRITING THIS SCROLLTEXT WE DON'T KNOW WHETER WE WILL HAVE ROOM FOR IT ON THE DISK OR NOT.  THIS DEMO WAS CODED IN A FEW HOURS, SO THERE'S NO BIG LOSS IF WE CANT SQUEEZE IT ONTO THE DISK.   WE DON'T GET ANY INSPIRATION WHAT TO WRITE, SO PERHAPS WE'LL TALK A BIT ABOUT TABLE TENNIS..  ON THE LAWN OUTSIDE NICK'S VILLA, THERE'S A PING-PONG-TABLE.  WHEN ALL THE MEMBERS OF TCB, TANIS AND A.D. ARE HERE, NICK'S COMPUTER-ROOM GETS VERY CROWDED, SO WE HAVE TOURNAMENTS IN TABLE TENNIS.   IF WE GIVE YOU SOME FACTS, YOU SHOULD BE ABLE TO FIGURE OUT WHO IS THE BEST AT TABLE TENNIS....       AN COOL THINKS HE IS BETTER THAN NICK.   TANIS THINKS HE IS BETTER THAN AN COOL.  EVERYBODY WIPES THE FLOOR WITH A.D.   NICK IS BETTER THAN JAS.   TANIS HAS NO CHANCE WHEN HE'S PLAYING NICK.  TANIS HAS NEVER PLAYED JAS.   AN COOL THINKS HE IS BETTER THAN TANIS.   NICK IS BETTER THAN AN COOL.  JAS IS NOT AS GOOD AS AN COOL NOR TANIS.   JAS THINKS HE IS THE BEST.          NOW YOU SHOULD HAVE BEEN ABLE TO FIGURE OUT WHO IS THE BEST AT TABLE TENNIS, OR AT LEAST WHO WAS ON THE KEYBOARD WHEN THIS SCROLLTEXT WAS WRITTEN......    ";

// The logo, drawn once. mylogo.setmidhandle() + draw(mycanvas,340,50) puts its
// top-left at canvas 2x (130,17); the artwork's own 2x grid is offset by a row,
// so its first 1x row lands on canvas 1x row 9.
const LOGO_W: usize = 210;
const LOGO_H: u16 = 33;
const LOGO_X: i32 = OX + 65;
const LOGO_Y: u16 = OY + 9;

// screen.js: `if (pos_scroll>1872) pos_scroll=0` — the last index it ever reads,
// one short of the table's 1873 entries (the odd entries are never visited).
const MOVESCROLL_LAST: usize = 1872;

comptime {
    if (movescroll_b.len != (MOVESCROLL_LAST + 1) * 2) @compileError("movescroll.dat is not 1873 u16 entries");
    // clearStrip/drawGlyph write STRIP_H rows at OY + movescroll/2 with no
    // runtime clamp, so prove HERE that the band stays on the plane. (Asserting
    // it at run time would cost nothing but do nothing: std.debug.assert is a
    // no-op in ReleaseSmall.)
    @setEvalBranchQuota(20_000);
    var top: u16 = 0;
    var i: usize = 0;
    while (i <= MOVESCROLL_LAST) : (i += 2) top = @max(top, movescroll(i) >> 1);
    if (OY + top + STRIP_H > zg.PHYSICAL_HEIGHT) @compileError("the scroll strip would run off the bottom of the plane");
}

const Slot = struct { x: i32, glyph: u8 };

pub const Demo = struct {
    // NOTE: demo_main holds the cart as `undefined`, so a field's declared
    // default never runs. Every one of these is assigned in init().
    vbl: f32,
    pos_scroll: usize,
    strip_y: u16, // plane row the strip is drawn at this frame
    erase_y: u16, // ...and where it was last frame, the band to erase
    slots: [NB_SLOTS]Slot,
    scroffset: usize,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("tcb_colorshock: THE CAREBEARS / COLORSHOCK 2", .{});

        const bg: *LogicalFB = &zigos.lfbs[0];
        bg.is_enabled = true;
        pan_row = 0; // module state, so a re-entered scene must not inherit it
        bg.setOverscanScrollPlane(BUF_W, BUF_H);
        paintPanBuffer(bg);
        installRowPalette(bg, 0);
        bg.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, panHbl);

        const ink: *LogicalFB = &zigos.lfbs[1];
        ink.is_enabled = true;
        ink.openBorders(.all); // its own overscan buffer AND its own flicker HBL
        ink.setPalette(ink_pal);
        ink.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        blit(ink, logo_b, LOGO_W, LOGO_X, LOGO_Y, LOGO_W, LOGO_H, false);

        self.vbl = 0.0;
        self.pos_scroll = 0;
        self.strip_y = OY + (movescroll(0) >> 1);
        self.erase_y = self.strip_y;
        self.scroffset = 0;
        for (&self.slots, 0..) |*slot, i| {
            slot.x = SCROLL_START + @as(i32, @intCast(i)) * GLYPH_W;
            slot.glyph = self.nextChar();
        }

        zg.requestSong(MUSIC);
    }

    fn nextChar(self: *Demo) u8 {
        const c = SCROLL_TEXT[self.scroffset];
        self.scroffset += 1;
        if (self.scroffset >= SCROLL_TEXT.len) self.scroffset = 0;
        return if (c >= FIRST_CHAR and c <= LAST_CHAR) c - FIRST_CHAR else 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.pan(&zigos.lfbs[0]);

        // The table is read BEFORE the step, so the strip visits 0,2,...,1872.
        if (self.pos_scroll > MOVESCROLL_LAST) self.pos_scroll = 0;
        self.erase_y = self.strip_y;
        self.strip_y = OY + (movescroll(self.pos_scroll) >> 1);
        self.pos_scroll += 2;

        for (&self.slots) |*slot| {
            slot.x -= SCROLL_SPEED;
            if (slot.x <= -GLYPH_W) {
                slot.x = SCROLL_START + (slot.x + GLYPH_W);
                slot.glyph = self.nextChar();
            }
        }
    }

    // go(): vbl += 0.8, which CODEF lets grow forever (f64). Here it is wrapped
    // at 400.0 — a whole number of turns for both sin(vbl*PI/100) (250 frames)
    // and cos(vbl*PI/200) (500) — so vbl stays in [0,400) and one f32 step keeps
    // ~5 significant digits however long the screen runs.
    // It does NOT come back bit-exact: 500 additions of the f32 nearest 0.8 land
    // on 399.99847, so the wrap fires one frame late and leaves a residue of
    // ~0.798. The Lissajous phase therefore creeps (about 9 frames' worth over
    // 3M frames) instead of repeating exactly. Nothing reads the phase but @sin
    // and @cos, so that is invisible; what matters for the pan bound is that
    // sx is clamped and sy is taken mod TILE_H, which holds for ANY vbl.
    fn pan(self: *Demo, bg: *LogicalFB) void {
        const x = 200.0 + @sin(self.vbl * std.math.pi / 100.0) * 200.0;
        const y = 158.0 + @cos(self.vbl * std.math.pi / 200.0) * 150.0;
        const sx: i32 = @intFromFloat(@round(x));
        const sy: i32 = @intFromFloat(@round(y));
        pan_row = @intCast(@mod(sy, @as(i32, TILE_H)));
        bg.setScroll(@intCast(std.math.clamp(sx, 0, 400)), pan_row);

        self.vbl += 0.8;
        if (self.vbl >= 400.0) self.vbl -= 400.0;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const ink: *LogicalFB = &zigos.lfbs[1];
        clearStrip(ink, self.erase_y);

        // The original's order: the glyphs into the strip, then scroll_acc over
        // them. The strip clips at its own 300-wide edges, so a glyph leaving it
        // is cut rather than drawn on the screen behind.
        for (self.slots) |slot| drawGlyph(ink, slot.glyph, slot.x, self.strip_y);
        blit(ink, acc_b, 300, STRIP_X, self.strip_y, 300, STRIP_H, true);
    }
};

fn movescroll(i: usize) u16 {
    return std.mem.readInt(u16, movescroll_b[i * 2 ..][0..2], .little);
}

// Repeat the 288-row tile down the pan buffer. The window wraps seamlessly
// wherever it lands because the artwork is exactly 288-periodic.
fn paintPanBuffer(bg: *LogicalFB) void {
    var y: usize = 0;
    while (y < BUF_H) : (y += 1) {
        const src = fond_b[(y % TILE_H) * TILE_W ..][0..TILE_W];
        @memcpy(bg.fb[y * BUF_W ..][0..TILE_W], src);
    }
}

fn installRowPalette(bg: *LogicalFB, row: usize) void {
    const src = fond_rows[row * ROW_PAL_BYTES ..][0..ROW_PAL_BYTES];
    @memcpy(@as([*]u8, @ptrCast(bg.palette))[0..ROW_PAL_BYTES], src);
}

// Erase where the strip was — the exact band drawn last frame, so nothing ever
// trails. The logo sits at plane rows 49..81 and the strip can only reach rows
// 85..207 (movescroll's even entries are 91..283, halved, +OY, +STRIP_H), so the
// logo is never touched and never needs redrawing.
fn clearStrip(ink: *LogicalFB, y: u16) void {
    var row: u16 = 0;
    while (row < STRIP_H) : (row += 1) {
        const at = @as(usize, y + row) * zg.PHYSICAL_WIDTH + STRIP_XU;
        @memset(ink.fb[at..][0..STRIP_WU], 0);
    }
}

// An image blit clipped to the plane, x signed. `keep_ink` skips index 0 so an
// overlay lets what is under it through (scroll_acc over the text); the glyphs
// paint onto a cleared band, so they write every pixel.
fn blit(ink: *LogicalFB, img: []const u8, img_w: usize, x: i32, y: u16, w: usize, h: u16, keep_ink: bool) void {
    const from: i32 = @max(0, -x);
    const to: i32 = @min(@as(i32, @intCast(w)), @as(i32, zg.PHYSICAL_WIDTH) - x);
    if (from >= to) return;
    var row: u16 = 0;
    while (row < h) : (row += 1) {
        const src = row * img_w;
        const dst = @as(usize, y + row) * zg.PHYSICAL_WIDTH;
        var i: i32 = from;
        while (i < to) : (i += 1) {
            const v = img[src + @as(usize, @intCast(i))];
            if (keep_ink and v == 0) continue;
            ink.fb[dst + @as(usize, @intCast(x + i))] = v;
        }
    }
}

// One glyph, clipped to the 300-wide strip the original draws into, then placed
// on the plane. The clip is the same on every row, so it is computed once.
fn drawGlyph(ink: *LogicalFB, glyph: u8, x: i32, strip_y: u16) void {
    const tile_x: usize = (@as(usize, glyph) % GLYPH_COLS) * @as(usize, GLYPH_W);
    const tile_y: usize = (@as(usize, glyph) / GLYPH_COLS) * @as(usize, GLYPH_H);
    const from: i32 = @max(0, -x);
    const to: i32 = @min(GLYPH_W, STRIP_W - x);
    if (from >= to) return;

    var gy: u16 = 0;
    while (gy < GLYPH_H) : (gy += 1) {
        const src = (tile_y + gy) * FONT_SHEET_W + tile_x;
        const dst = @as(usize, strip_y + gy) * zg.PHYSICAL_WIDTH + STRIP_XU;
        var gx: i32 = from;
        while (gx < to) : (gx += 1) {
            ink.fb[dst + @as(usize, @intCast(x + gx))] = font_b[src + @as(usize, @intCast(gx))];
        }
    }
}
