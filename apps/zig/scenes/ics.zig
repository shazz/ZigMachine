// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const readU16Array = zg.readU16Array;
const readI16Array = zg.readI16Array;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const RenderTarget = zg.RenderTarget;
const RenderBuffer = zg.RenderBuffer;
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;
const Sprite = zg.Sprite;
const Background = zg.Background;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// David Whittaker, "Leatherneck" (1988). Carries 3 subtunes; the player
// takes the image's own default.
const MUSIC = "leatherneck.sndh";

// scrolltext

const fonts_b = @embedFile("../assets/screens/ics/font_noics_pal.raw");
const SCROLL_TEXT = "    ICS PRESENTS YOU:         BUMPY'S     GAME CRACKED BY THE THREAT        ORIGINAL BY SLASH OF FRANCE       THIS INTRO WAS CODED, DESIGNED FOR I.C.S. BY  -EL PISTOLERO-..... (MANY THANKS!)     JUST AFTER THIS LITTLE INTRO YOU CAN READ A MESSAGE SENT TO SLASH BY SLEDGE, I THINK YOU'LL BE SURPRISED...           I WANT TO SAID A BIG HI TO  'NUKE' OUR NEW CRACKER, HE LIVES IN FRANCE LIKE A LOT OF MEMBERS OF ICS.      BIG HELLO TO SKINHEAD FROM GERMANY WHO GIVE US VERY HOT ORIGINALS (LIKE STONE AGE).      BIG HI TO SLASH AND BELGARION WHO ARE VERY GOOD/COOL GUYS!!!      AND OF COURSE I DON'T FORGET MR.FLY.        GREETINGS TO: SCSI, CYNIX, POMPEY PIRATES, DANNY FROM SINGAPORE, FUZION, THE REPLICANTS, AND YOU, IF YOU WANT!!!        WE LOOOKING FOR SUPPLIERS ALL OVER THE WORLD, IF YOU ARE INTRESTED WRITE TO THE P.O. BOX OR CALL ONE OF OUR BOARD.       THIS ALL FOR THIS TIME, SEE YOU SOON....              ";
const SCROLL_CHAR_WIDTH = 16; 
const SCROLL_CHAR_HEIGHT = 16;
const SCROLL_SPEED = 3;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH / SCROLL_CHAR_WIDTH + 1;
const g_y_offset_table_b = readI16Array(@embedFile("../assets/screens/ics/scroller_sin.dat"));

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/ics_logo_pal.dat"));
const grid_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/grid_large_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/ics/raster_pal.dat"));

// logo
const logo_b = @embedFile("../assets/screens/ics/ics_logo.raw");
const grid_b = @embedFile("../assets/screens/ics/grid_large.raw");


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u8 = 0;

// The bottom 37 rows of the screen: black, with the 137x31 logo at (WIDTH/2-68, HEIGHT-29) in
// it, as palette slots LOGO_SLOT + the logo's own index (the old plane 2 drew these once).
const BAND_ROWS = 37;
const BAND_TOP = HEIGHT - BAND_ROWS;
const LOGO_SLOT = 100;
const LOGO_W = 137;
const LOGO_H = 31;
var logo_band: [WIDTH * BAND_ROWS]u8 align(4) = undefined;

fn buildBand() void {
    @memset(&logo_band, LOGO_SLOT); // the logo palette's index 0 is black
    const top = HEIGHT - 29 - BAND_TOP; // the logo's first row, in band rows
    for (0..LOGO_H) |y| {
        if (top + y >= BAND_ROWS) break; // the plane ends at row 199
        for (0..LOGO_W) |x| {
            const idx = logo_b[y * LOGO_W + x];
            if (idx != 0) logo_band[(top + y) * WIDTH + (WIDTH / 2 - 68) + x] = LOGO_SLOT + idx;
        }
    }
}
var chisel: zg.Blitter = .{}; // the grid window copy; init() points it at the video region

// The scroller's letters are drawn into this strip first. The wave moves a letter
// at most 39 rows down (the sine table's peak), so nothing below row 54 is ever
// drawn: the strip is 56 rows, not the 200 of the plane (it used to be cleared,
// copied onto itself and copied to the plane, all whole).
const TEXT_ROWS = 56;
const ROW_WORDS = WIDTH / 4;
var text_strip: [WIDTH * TEXT_ROWS]u8 align(4) = undefined;
var strip_buffer: RenderBuffer = .{ .buffer = &text_strip, .width = WIDTH, .height = TEXT_ROWS };
// G[b]: strip rows b, b+16, b+32, b+48 merged, the topmost opaque pixel winning.
var merged: [16][ROW_WORDS]u32 = undefined;
// The grid sprite's offset, from the cart's own wobble (always -32..-1 each way).
var grid_dx: i32 = -32;
var grid_dy: i32 = -32;
const GRID_W = 384;
const SCROLL_TOP = 32; // the plane's first row shows scroll row 32
const SCROLL_PLANE_ROWS = 200 - SCROLL_TOP; // the rows of the plane the scroller writes

/// 0xFF in every byte of `w` that is not 0.
inline fn opaqueBytes(w: u32) u32 {
    const high = (((w & 0x7f7f7f7f) +% 0x7f7f7f7f) | w) & 0x80808080;
    return (high >> 7) * 0xFF;
}

/// Strip rows base, base+16, ... up to `last`, merged into `out`: each pixel is
/// the first non-zero one going down the chain. That is what copying every
/// non-zero pixel 16 rows down, row after row (the 'copy 9 times' pass), left.
fn mergeChain(out: *[ROW_WORDS]u32, base: usize, last: usize) void {
    const words: *const [TEXT_ROWS * ROW_WORDS]u32 = @ptrCast(&text_strip);
    for (out, 0..) |*o, i| {
        var acc: u32 = 0; // kept in a register: `out` may be the plane, a store each
        var row = base;
        while (row <= last and row < TEXT_ROWS) : (row += 16) {
            acc |= words[row * ROW_WORDS + i] & ~opaqueBytes(acc);
        }
        o.* = acc;
    }
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // The sealed machine fires this HBL on LOGICAL lines 0..199 (not the old
    // physical 40..239), so index the raster palette by `line` directly. Rasters
    // cover the grid/scroller area (0..164); entry 1 is blanked for the logo below.
    if (line < 165) {
        fb.setPaletteEntry(1, rasters_b[line]);
    }
    if (line == 165) {
        fb.setPaletteEntry(1, back_color);
    }

    _ = zigos;
    _ = col;
}

pub const Demo = struct {
  
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    grid: Sprite = undefined,
    scroller_target: RenderTarget = undefined,
    sin_counter: zg.fixtrig.Angle = 0, // u32 turns, wraps exactly at 2 PI

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_scroller);        

        chisel.init();
        @memset(&text_strip, 0);
        self.scroller_target = .{ .render_buffer = &strip_buffer };
        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, &g_y_offset_table_b, false);

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 

        // set oversized grid
        fb.setPalette(grid_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });            
        self.grid.init(fb.getRenderTarget(), grid_b, 384, 288, 0, 0, null, null); 

        // The logo plane is gone: its black band and the logo are one more picture drawn on the
        // grid's plane, over the grid (the logo plane lay above it), in slots 100.. of its palette.
        // FRESCO paints every enabled plane (1.09 Mc each), and this one only ever held the band.
        for (0..8) |i| fb.setPaletteEntry(@intCast(LOGO_SLOT + i), logo_pal[i]);
        buildBand();

        self.sin_counter = 0;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();

        // sin/cos(-counter) * 32 * 3.2, truncated: 102.4 in Q16.16 is 6710886
        const neg = 0 -% self.sin_counter;
        const f_sin: i16 = @intCast(@divTrunc(@as(i64, zg.fixtrig.sin(neg)) * 6710886, 1 << 32));
        const f_cos: i16 = @intCast(@divTrunc(@as(i64, zg.fixtrig.cos(neg)) * 6710886, 1 << 32));
        const delta_x = -32 + @mod(f_sin, 32);
        const delta_y = -32 + @mod(f_cos, 32);

        self.grid.update(delta_x, delta_y, null, null);
        grid_dx = delta_x;
        grid_dy = delta_y;

        self.sin_counter +%= zg.fixtrig.angle(0.034);
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();
        renderScroller(&zigos.lfbs[0]);
        renderGrid(&zigos.lfbs[1]);
        chisel.blitImage(&zigos.lfbs[1], 0, BAND_TOP, &logo_band, WIDTH, 0, 0, WIDTH, BAND_ROWS, null);

        _ = elapsed_time;

    } 
};

/// Plane 0 = scroll rows 32.. of the strip once every non-zero pixel has been
/// copied 16 rows down, over and over. Rows from 54 down are the same 16 merged
/// rows repeating, so those are merged once a frame and copied.
fn renderScroller(fb: *LogicalFB) void {
    for (&merged, 0..) |*g, b| mergeChain(g, b, TEXT_ROWS - 1);
    const out: [*]u32 = @ptrCast(@alignCast(fb.fb));
    const first_merged = TEXT_ROWS - 1 - SCROLL_TOP; // from this plane row down the rows are merged[row % 16]
    for (0..first_merged) |k| mergeChain(out[k * ROW_WORDS ..][0..ROW_WORDS], (k + SCROLL_TOP) % 16, k + SCROLL_TOP);
    // The rest is the 16 merged rows over and over: CHISEL copies them out in blocks of up to 16
    // rows (SCROLL_TOP is a multiple of 16, so plane row k shows merged[k % 16]).
    const rows: [*]const u8 = @ptrCast(&merged);
    var k: usize = first_merged;
    while (k < SCROLL_PLANE_ROWS) {
        const n = @min(16 - k % 16, SCROLL_PLANE_ROWS - k);
        chisel.blitImage(fb, 0, @intCast(k), rows[0 .. 16 * WIDTH], WIDTH, 0, @intCast(k % 16), WIDTH, @intCast(n), null);
        k += n;
    }
}

/// Plane 1 = the 384x288 grid seen through a 320x200 window at (-dx, -dy): what
/// the sprite's clipped, transparent-skipping draw over a cleared plane left.
/// One CHISEL copy of the window (the CPU packed and stored 16,000 words a frame).
fn renderGrid(fb: *LogicalFB) void {
    const x0: u16 = @intCast(-grid_dx);
    const y0: u16 = @intCast(-grid_dy);
    chisel.blitImage(fb, 0, 0, grid_b, GRID_W, x0, y0, WIDTH, 200, null);
}
