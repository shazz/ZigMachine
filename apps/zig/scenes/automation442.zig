// --------------------------------------------------------------------------
// AUTOMATION COMPACT DISK 442 PART A — the Ghostbusters II menu.
//   original: coder VAPOUR, gfx TLB, music MAD MAX (Automation / Blood Angel)
//   CODEF HTML5 remake (screen 420) by Ayoros / Hemoroids, MIT-licensed
//
// Ported from prototypes/codef/420/screen.js. The CODEF canvas is 640x400 = an
// ST 320x200 doubled, so every coordinate here is the original's halved.
//
// What is on screen: one scrolling "PIRACY IS FUN" skull background and one
// 32px-tall horizontal scrolltext. That is the whole screen.
//
// DELIBERATE DEPARTURES FROM THE REMAKE (1-4 asked for / agreed):
//  1. The fake AtariDecrunch depack intro (screen.js:121, init_intro) is NOT
//     ported: ZigMachine has that look as a REAL depack effect (zx0.Fx.automation).
//  2. intro()/intro2() (screen.js:151-162) ramp a white then a black full-screen
//     overlay to alpha 0.1 over a canvas that is already black — an all-but-
//     invisible flicker. Omitted.
//  3. The background is not re-blitted per frame. CODEF draws the whole
//     1280x800 sheet every frame at (pos_x,pos_y); we paint ONE tiled 720x561
//     buffer at init and pan it with the hardware (setScroll = one register
//     write). Zero per-pixel work per frame for the background.
//  4. BOTH planes are OVERSCAN, so the skull AND the scroller fill the borders —
//     400x280 instead of the remake's 320x200. Borders are earned the ST way:
//     flickerBorder() from each plane's own HBL at OVERSCAN_MAGIC_X, every line.
//     (Each enabled overscan plane needs its own handler: the machine replays a
//     plane's HBLs while rendering THAT plane.)
//  5. The scrolltext plane is never cleared. screen.js clears its scroll canvas
//     every frame (screen.js:167); the fifteen glyph slots provably repaint every
//     column of the 400-wide plane, so the blit is the erase. The proof — steady
//     state AND the first 120 frames — is at the call site in render().
//
// Everything else is the original's own numbers: piracy_move()'s bgcount
// thresholds, the scrolltext's slot arithmetic, the 374-row artwork period.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
// One skull tile, exactly ONE tiling period; the machine does the tiling (see
// tools/private_tools/automation442_assets.py). Measured on the sheet: the
// period is 640x374 source px = 320x187 ST, and 374 is precisely the original's
// pos_y=-374 wrap constant — so the remake's vertical wrap is seamless and this
// port's mod-187 wrap reproduces it exactly.
const piracy_b = @embedFile("../assets/screens/automation442/piracy.raw");
const piracy_pal = convertU8ArraytoColors(@embedFile("../assets/screens/automation442/piracy_pal.dat"));
const TILE_W: u16 = 320;
const TILE_H: u16 = 187;

// 10x6 grid of 32x32 glyphs, first char 32 (myfont.initTile(64,64,32), halved).
const font_b = @embedFile("../assets/screens/automation442/font.raw");
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/automation442/font_pal.dat"));
const FONT_SHEET_W: u16 = 320;
const GLYPH_COLS: usize = 10;
const GLYPH_ROWS: usize = 6;
const GLYPH_W: i32 = 32;
const GLYPH_H: u16 = 32;
const FIRST_CHAR: u8 = 32;
const LAST_CHAR: u8 = 91; // 10*6 tiles from 32

// MUSIC. The original plays a YM register dump, "Jinx 1.ym" (screen.js:130) —
// deprecated here. Best SNDH match by tools/private_tools/sndh_index.py:
// Mad_Max/Games/Jinks.sndh — same composer (MAD MAX), same title, FLAG ~y,
// 2 subtunes; subtune 1 matches the "Jinx 1" filename. (Mad_Max/Demos/
// Jinks_Digi.sndh is FLAG ~ay = STE DMA and would play silence: not used.)
const MUSIC = "Jinks.sndh";
const MUSIC_TUNE: u8 = 1;

// --------------------------------------------------------------------------
// Background: an OVERSCAN plane panned by the hardware
// --------------------------------------------------------------------------
// The window is 400x280 and the content repeats every 320x187, so a seamless
// wrap needs w >= 400+320 = 720 and h >= 280+187 = 467; 561 = 3*187 keeps the
// fill an exact number of tiles. 720*561 = 403920 B of the 1 MiB VRAM pool (with
// the four 64000 B planes the machine allocates at boot — the bump allocator
// never reclaims plane 0's — and the text plane's 112000 B, 771920 B in all).
//
// BOUNDS. panBackground() only ever scrolls to (sx, sy) with sx = -pos_x mod 320
// and sy = -pos_y mod 187, so sx <= 319 and sy <= 186 whatever pos_x/pos_y do.
// renderPlaneOverscan() reads buf[(sy + y) * BUF_W + sx + x] for y < 280, x < 400
// — never across a row boundary — so the last byte it can touch is
//   (186 + 279) * 720 + (319 + 399) = 334800 + 718 = 335518,
// inside the 403920-byte buffer.
// The comptime check below is that inequality; it is what keeps an out-of-bounds
// read (silent VRAM corruption, not a trap) impossible rather than unlikely.
const BUF_W: u16 = 720;
const BUF_H: u16 = 3 * TILE_H;

comptime {
    const max_sx = TILE_W - 1;
    const max_sy = TILE_H - 1;
    if (max_sx + zg.PHYSICAL_WIDTH > BUF_W) @compileError("pan buffer too narrow: the window would read past a row");
    if (max_sy + zg.PHYSICAL_HEIGHT > BUF_H) @compileError("pan buffer too short: the window would read past the buffer");
    if (piracy_b.len != @as(usize, TILE_W) * @as(usize, TILE_H)) @compileError("piracy.raw is not one TILE_W x TILE_H period");
    // drawGlyph indexes the sheet up to glyph LAST_CHAR-FIRST_CHAR = the last of
    // the 10x6 grid; that is exactly the last byte of the file.
    if (font_b.len != @as(usize, FONT_SHEET_W) * @as(usize, GLYPH_H) * GLYPH_ROWS) @compileError("font.raw is not a 10x6 grid of GLYPH_W x GLYPH_H tiles");
    if (LAST_CHAR - FIRST_CHAR + 1 != GLYPH_COLS * GLYPH_ROWS) @compileError("FIRST_CHAR..LAST_CHAR does not match the glyph grid");
}

// --------------------------------------------------------------------------
// Scrolltext (lib/codef_scrolltext.js, scrolltext_horizontal)
// --------------------------------------------------------------------------
// wide = ceil(dst_w/fontw)+1 and the loops run i <= wide, so there are wide+1
// slots starting at wide*fontw + i*fontw. The remake's destination is the
// 320-wide screen (wide = 11, 12 slots); ours is the 400-wide OVERSCAN plane, so
// the same formula gives wide = ceil(400/32)+1 = 14 and FIFTEEN slots — the
// scroller runs out through both side borders instead of stopping at the window.
//
// This screen passes no sinparam, so the text is flat; and its text contains no
// '^', so the lib's ^P/^S/^C escapes are not exercised. The lib sorts slots by
// posx before drawing — with glyphs exactly one glyph-width apart nothing ever
// overlaps, so the sort cannot change a pixel and is not ported.
const WIDE: i32 = 14;
const NB_SLOTS: usize = 15;
const SCROLL_START: i32 = WIDE * GLYPH_W; // 448
const SCROLL_SPEED: i32 = 4; // 8 in CODEF
// mycanvas_scroll is drawn at y=330 => 165 logical. The text plane is overscan,
// so its coordinates are PHYSICAL: logical 165 is physical 165+40.
const SCROLL_Y: u16 = 165 + zg.VERTICAL_BORDERS_HEIGHT;

const SCROLL_TEXT = "        VAPOUR PRESENTS AUTOMATION COMPACT DISK 442 PART A...     THIS DISK ONLY CONTAINS GHOSTBUSTERS II WHICH WAS PACKED FROM FOUR DISKS TO ONE AND A BIT.   THE BIT IS ON 442 PART B.   THANKS MUST GO TO BLOOD ANGEL FOR THIS NICE LITTLE INTRO...  AND TO KRYTEN FOR THE HACKING AND PACKING.  THANKS ALSO TO MOB FOR THE ORIGINAL.      SEND SOME MORE TO THE BALD EAGLE IF YOU WANT ME TO USE ANY OTHERS YOU WRITE...   CHEERS...  THIS FONT TLB                   ";

const Slot = struct { x: i32, glyph: u8 };

pub const Demo = struct {
    // piracy_move() state. NOTE: struct defaults never run (demo_main holds the
    // cart as `undefined`), so init() assigns every one of these explicitly.
    bgcount: i32,
    pos_x: i32,
    pos_y: i32,

    slots: [NB_SLOTS]Slot,
    scroffset: usize,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("automation442: AUTOMATION CD 442 PART A", .{});

        const bg: *LogicalFB = &zigos.lfbs[0];
        bg.is_enabled = true;
        bg.setPalette(piracy_pal);
        bg.setOverscanScrollPlane(BUF_W, BUF_H);
        bg.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, zg.flickerAllHbl);
        paintTiled(bg);

        const text: *LogicalFB = &zigos.lfbs[1];
        text.is_enabled = true;
        text.setPalette(font_pal);
        text.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        text.openBorders(.all); // its own overscan buffer AND its own flicker HBL

        self.bgcount = 0;
        self.pos_x = 0;
        self.pos_y = -200; // -400 in CODEF
        self.scroffset = 0;
        for (&self.slots, 0..) |*slot, i| {
            slot.x = SCROLL_START + @as(i32, @intCast(i)) * GLYPH_W;
            slot.glyph = self.nextChar();
        }

        zg.requestSongTune(MUSIC, MUSIC_TUNE);
    }

    fn nextChar(self: *Demo) u8 {
        const c = SCROLL_TEXT[self.scroffset];
        self.scroffset += 1;
        if (self.scroffset >= SCROLL_TEXT.len) self.scroffset = 0;
        return if (c >= FIRST_CHAR and c <= LAST_CHAR) c - FIRST_CHAR else 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.panBackground(&zigos.lfbs[0]);
        for (&self.slots) |*slot| {
            slot.x -= SCROLL_SPEED;
            if (slot.x <= -GLYPH_W) {
                slot.x = SCROLL_START + (slot.x + GLYPH_W);
                slot.glyph = self.nextChar();
            }
        }
    }

    // piracy_move(), halved. The two `if(pos_x==-640)` / `if(pos_x==-0)` lines
    // in the original assign a variable to itself and are dropped.
    fn panBackground(self: *Demo, bg: *LogicalFB) void {
        self.bgcount += 16;
        if (self.bgcount <= 640) self.pos_x -= 8;
        if (self.bgcount > 640 and self.bgcount < 3000) self.pos_y += 1;
        if (self.bgcount > 3000 and self.bgcount <= 3640) self.pos_x += 8;
        if (self.bgcount > 3640 and self.bgcount < 6000) self.pos_y += 1;
        if (self.bgcount > 6000) self.bgcount = 0;

        // CODEF draws the sheet AT (pos_x,pos_y) with both <= 0, i.e. shifted up
        // and left; the hardware equivalent moves the read window the other way.
        // Wrapping on the tile period IS the original's `if(pos_y==0) pos_y=-374`
        // — that reset is mod-374 arithmetic on a 374-periodic image.
        bg.setScroll(wrap(-self.pos_x, TILE_W), wrap(-self.pos_y, TILE_H));
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const text: *LogicalFB = &zigos.lfbs[1];
        // No per-frame clear (screen.js:167 clears; we do not). Why that is safe,
        // in two parts — the steady state AND the ~120 frames before it:
        //
        //  * The slots are always the exact progression L, L+32, ... L+448: a slot
        //    recycles from x <= -32 to 448 + (x+32), i.e. it becomes the rightmost
        //    and the set stays contiguous. So once L has reached <= 0, L stays in
        //    (-32, 0] (recycling turns L into L+28) and the fifteen glyphs cover
        //    [L, L+480) ⊇ [0, 400): every column is rewritten every frame, and a
        //    glyph's 4-column trail is covered by its right-hand neighbour.
        //  * Before that — init puts the slots at 448..896, all off screen, and
        //    they take 112 frames to cover column 0 — the text is simply scrolling
        //    IN from the right over a buffer openBorders() cleared to index 0, and
        //    a slot still clipped at the right edge draws through to column 399
        //    every frame, so it leaves nothing behind either.
        //
        // Transparent glyph pixels are written too, so the blit is also the erase.
        for (&self.slots) |slot| drawGlyph(text, slot.glyph, slot.x);
    }
};

fn wrap(v: i32, period: i32) u32 {
    return @intCast(@mod(v, period));
}

// Replicate the tile across the pan buffer. 720 is not a multiple of 320, so the
// last 80 columns are the head of a tile — which is exactly what the period
// demands, so the buffer is 320-periodic across its whole width and the window
// wraps seamlessly wherever it lands.
fn paintTiled(bg: *LogicalFB) void {
    var y: u16 = 0;
    while (y < BUF_H) : (y += 1) {
        const src = piracy_b[@as(usize, y % TILE_H) * TILE_W ..][0..TILE_W];
        const dst = bg.fb[@as(usize, y) * BUF_W ..][0..BUF_W];
        var x: usize = 0;
        while (x < BUF_W) : (x += TILE_W) {
            const n = @min(@as(usize, TILE_W), BUF_W - x);
            @memcpy(dst[x..][0..n], src[0..n]);
        }
    }
}

// One glyph, clipped to the 400-wide overscan plane. The x clip is the same on
// every row, so it is computed once instead of per pixel.
fn drawGlyph(text: *LogicalFB, glyph: u8, x: i32) void {
    const tile_x: usize = (@as(usize, glyph) % GLYPH_COLS) * @as(usize, GLYPH_W);
    const tile_y: usize = (@as(usize, glyph) / GLYPH_COLS) * @as(usize, GLYPH_H);
    const from: i32 = @max(0, -x);
    const to: i32 = @min(GLYPH_W, @as(i32, zg.PHYSICAL_WIDTH) - x);
    if (from >= to) return;

    var gy: u16 = 0;
    while (gy < GLYPH_H) : (gy += 1) {
        const row = (tile_y + gy) * FONT_SHEET_W + tile_x;
        var gx: i32 = from;
        while (gx < to) : (gx += 1) {
            const v = font_b[row + @as(usize, @intCast(gx))];
            text.setPixelValue(@intCast(x + gx), SCROLL_Y + gy, v);
        }
    }
}
