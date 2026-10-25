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
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;
const Background = zg.Background;

const Console = zg.Console;
const letter_rows = @import("scrolltext_rows.zig");

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// David Whittaker, "Renegade" (1987).
const MUSIC = "renegade.sndh";

// scrolltext
pub const NB_FONTS: u8 = 11;
// 4-aligned (a plain @embedFile is align 1): the letters' rows then copy word to
// word into the strip, not four byte loads a word (the board's memcpy, misaligned).
const fonts_b: *align(4) const [@embedFile(fonts_path).len]u8 = &fonts_words;
const fonts_words: [@embedFile(fonts_path).len]u8 align(4) = @embedFile(fonts_path).*;
const fonts_path = "../assets/screens/df/fonts2_pal.raw";
const SCROLL_TEXT = "               TESTDRIVE WAS CRACKED BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP.    THIS INTRO WAS CODED BY CHAOS, INC., TOO.  FIRST OF ALL I WANT TO THANK GUIDO OF THE MAD MAX COPORATION FOR THE ORIGINAL!      GREETINGS TO: NEW-MODE, ABC, QUESTLORD, JOE COOL, GREEN BERET CRACKERS, PSYCHO.     ALSO GREETINGS TO: 42-CREW, TNT-CREW, TNT, COPY SERVICE STUTTGART, TEX, CERTAINLY MAD MAX COPORATION AND, LAST BUT NOT LEAST, ACCOLADE!      WAIT FOR OUR NEXT INTRO, WHICH WILL INCLUDE SOME DIGISOUNDS.     HEY ACCOLADE, CAN'T YOU MAKE A BETTER SOUND? IT'S REALLY AWFUL AND BORING! SOME DIGISOUND, WHILE  THE CAR IS CRASHING?    WHY NOT?      THAT'S IT FOR TODAY.....   CHAOS, INC.                            WHAT'S UP FOLKS?                        YOU WAIT FOR THE END?           HERE IT IS!   ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 30;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df/fonts2_pal.dat"));
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df/top_logo_pal.dat"));

// rasters
// Each line's HBL loads its Color as one word, which traps on the board when
// misaligned. Indexed through a 4-aligned POINTER: a comptime-known array indexed
// by value is lowered to an anonymous align-1 copy, whatever its own align says.
const rasters_b: *align(4) const [256]Color = &rasters_words;
const top_rasters_b: *align(4) const [256]Color = &top_rasters_words;
const rasters_words: [256]Color align(4) = convertU8ArraytoColors(@embedFile("../assets/screens/df/rasters_pal.dat"));
const top_rasters_words: [256]Color align(4) = convertU8ArraytoColors(@embedFile("../assets/screens/df/top_raster_pal.dat"));

// logo
const logo_b = @embedFile("../assets/screens/df/top_logo.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u8 = 0;

// The scroller strip, in cart RAM (zg.mem, once per cart load; u32 elements so
// the clear is word stores). It must NOT live in the plane it is copied to: CHISEL
// tests a copy's source span against the destination span from the PLANE's base
// (zm_blit_chk.v), so a source inside the plane counts as an overlap and the copy
// runs ORDERED, each read waiting for the previous write. Three such in-plane
// copies of the strip took the board from 60 to 40 fps (553ffd60).
const STRIP_LEN: usize = @as(usize, WIDTH) * SCROLL_CHAR_HEIGHT;
var strip_owned: ?[]u32 = null;
fn stripWords() []u32 {
    if (strip_owned) |w| return w;
    const w = zg.mem.mustAlloc(u32, STRIP_LEN / 4);
    strip_owned = w;
    return w;
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_logo(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    const current_color: Color = top_rasters_b[raster_index];

    // Per-plane HBL: sealed machine fires on LOGICAL lines 0..199 (was physical 40..239), so drop the +40.
    if (line > 5 and line < 19 ) {
        fb.setPaletteEntry(255, current_color);
    }
    if (line == 20) {
        fb.setPaletteEntry(255, back_color);
    }

    _ = zigos;
    _ = col;
}

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Per-plane HBL: sealed machine fires on LOGICAL lines 0..199 (was physical 40..239), so drop the +40.
    if (line > 52 and line < 200 ) {
        fb.setPaletteEntry(1, rasters_b[(line - 52)]);
    }
    if (line == 200) {
        fb.setPaletteEntry(1, back_color);
    }

    _ = zigos;
    _ = col;
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Background = undefined,
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        self.logo.init(fb.getRenderTarget(), logo_b, 0);
        self.logo.render(); // the logo never changes: drawn once, not every frame
        
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_logo);   


        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);
        self.blitter.init();
        fb.clearFrameBuffer(0); // once: render() only ever rewrites the four scroller bands

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_scroller);        

        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 52, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();
        self.logo.update();

        self.frame_counter += 1;
        if (self.frame_counter == 2) {
            raster_index += 1;
            if (raster_index == 41) raster_index = 0;
            
           self.frame_counter = 0;
        }

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // The scroller strip is drawn ONCE, in cart RAM, then CHISEL places it four
        // times (rows 52, +39, +78, +117; every other row stays 0 from init): the
        // CPU used to @memcpy 28,800 B of copies a frame into the plane.
        const words = stripWords();
        for (words) |*w| w.* = 0;
        const strip: []u8 = std.mem.sliceAsBytes(words);
        letter_rows.draw(&self.scrolltext, strip.ptr, WIDTH, WIDTH, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT);
        const fb = &zigos.lfbs[1];
        inline for (.{ 0, 39, 78, 117 }) |rows| {
            self.blitter.blitImage(fb, 0, 52 + rows, strip, WIDTH, 0, 0, WIDTH, SCROLL_CHAR_HEIGHT, null);
        }

        _ = elapsed_time;

    }
};
