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
const RenderTarget = zg.RenderTarget;
const RenderBuffer = zg.RenderBuffer;

const Scrolltext = zg.Scrolltext;
const Background = zg.Background;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Rob Hubbard, "Thrust" (1988).
const MUSIC = "thrust.sndh";

// scrolltext

const fonts_b = @embedFile("../assets/screens/stcs/font40x34_c1.raw");
const SCROLL_TEXT = "                  PLEASE, READ ALL THIS SCROLL !!!           THE S.T.C.S. STRIKES BACK WITH THIS MEGA-NEWS CALLED                -- STARGOOSE --                  CRACKED ON 22-09-88 BY RATBOY FROM S.T.C.S.      THIS VERY NICE NEW INTRO WAS CODED AND DESIGNED BY RATBOY.    THE BLADERUNNERS ACRONYM WAS DESIGNED BY NINJA.     NEW ?     YOU THINK !                         YES, NEW !!!    NOW, THERE IS NO MORE ROOM FOR DOUBT CONCERNING THE FACT THAT THE S.T.C.S IS THE BEST COMPUTER GROUP EVER MADE IN FRANCE ON THE ATARI-ST.   SO, I WANT TO PRESENT YOU HIS 8 MEMBERS...                                   ACTARUS WHO CREATED THE GROUP AND WHO IS PERHAPS (CERTAINLY !) THE BEST SWAPPER IN EUROPE ON THE ATARI AND I WANT TO GREET HIM FOR HIS MORAL SUPPORT...         NINJA, THE NEW MEMBER WHO IS A VERY GOOD SWAPPER TOO (AND DESIGNER !!!)...     KICKSTART WHO SWAPS VERY WELL...    WHEN HE DOESN'T SLEEP  (THINK TO THE CSS CONVENTION !)...                     THE S.T.C.S. WAS COMPOSED BY ONE DEMOS PROGRAMMER CALLED BILLY OCTET AND BY FOUR CRACKERS TOO:       THE LORD,   BANZAI (WHO CRACKS VERY WELL WHEN HE DOESN'T SLEEP TOO !),  JABBERWOCKY AND RATBOY.       NOW IT'S TIME TO GREET SOME OTHER PEOPLE WHO MAKE A LOT OF GOOD THINGS ON THE ST.                                          MEGA-GIGA GREETINGS TO:   - THE BLADERUNNERS (ALL MEMBERS !) - TSUNOO -                      NORMAL GREETINGS TO:    -  THE UNION (HOWDY, ES, XXX INTERNATIONAL)  -  THE REPLICANTS (DO YOU KNOW WHAT THE WORD  'NEWS'  MEANS ?)  -  MCA  -  AH-A  -  THE BIG FOUR  -  WAS (NOT WAS)  -  FIRE CRACKERS  -  CSS  -  B.O.S.S  -                          FUCKING GREETINGS TO ALL VIRUS PROGRAMMERS, TEXT CHANGERS, CRACKED PROGRAMS SELLERS...              HAVE FUN WITH THIS NICE GAME.             PRESS THE SPACE BAR TO BEGIN.            BYE, BYE..........                 ";
const SCROLL_CHAR_WIDTH = 40; 
const SCROLL_CHAR_HEIGHT = 34;
const SCROLL_SPEED = 8;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = (WIDTH/SCROLL_CHAR_WIDTH) + 1;
const SCROLL_TOP_POS = 84;

// palettes
const font_pal1 = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/font40x34_c1_pal.dat"));
const font_pal2 = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/font40x34_c2_pal.dat"));
const font_pal3 = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/font40x34_c3_pal.dat"));
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/logo_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/rasters.dat"));

// logo
const logo_b = @embedFile("../assets/screens/stcs/logo.raw");


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
const strip = @import("stcs_strip.zig");
const letter_rows = @import("scrolltext_rows.zig");
const ScrollerPeriods = strip.Period;
var scroller_period: ScrollerPeriods = .threelines;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_hbl(zigos: *ZigOS, line: u16) void {

    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // GLOBAL HBL — fires on PHYSICAL lines 0..279 (borders included). The raster
    // gradient runs 107..239, then HOLDS its last colour on into the low border
    // (240..279) instead of going black. Above the raster stays black.
    if (line > 40 + 66) {
        const idx: usize = line - 40 - 66; // 1..
        zigos.setBackgroundColor(rasters_b[@min(idx, 133)]);
    } else {
        zigos.setBackgroundColor(back_color);
    }
}


fn handler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Per-plane HBL: sealed machine fires it on LOGICAL lines 0..199 (was physical
    // 40..239), so drop the +40. Rasters cover visible rows 66..199.
    if (line > 66 and line < 200) {
        fb.setPaletteEntry(0, rasters_b[line - 66]);
    } else {
        fb.setPaletteEntry(0, back_color);
    }

    _ = zigos;
    _ = col;
}

// The palette a line of the scroller plane wants. The HBL used to copy all 256
// entries on EVERY line (51,200 stores a frame, each a bus write on the board);
// the bands change it at most 3 times a frame, so it is installed only on a change.
fn scrollerPalette(line: u16) *const [256]Color {
    return switch (scroller_period) {
        .threelines => switch (line) {
            84...84 + SCROLL_CHAR_HEIGHT + 5 => &font_pal1,
            84 + SCROLL_CHAR_HEIGHT + 5 + 1...84 + 2 * (SCROLL_CHAR_HEIGHT + 5) => &font_pal2,
            84 + 2 * (SCROLL_CHAR_HEIGHT + 5) + 1...200 => &font_pal3,
            else => &font_pal1,
        },
        .inverted_mirror => switch (line) {
            84...117 => &font_pal1,
            118...150 => &font_pal2,
            151...200 => &font_pal3,
            else => &font_pal1,
        },
        .inverted => switch (line) {
            84...140 => &font_pal1,
            141...200 => &font_pal2,
            else => &font_pal1,
        },
        else => &font_pal1,
    };
}

// The palette plane 1 holds now (null: not one of the three, as after init).
var scroller_pal: ?*const [256]Color = null;

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const pal = scrollerPalette(line);
    if (scroller_pal != pal) {
        fb.setPalette(pal.*);
        scroller_pal = pal;
    }
    _ = zigos;
    _ = col;
}

// The scroller's off-screen strip: static, not init's stack frame (it outlives init).
// align(16): strip.zig copies it 16 bytes at a time as words, and a misaligned word load TRAPS on the board (~450 cycles each)
var scroller_pixels align(16) = [_]u8{0} ** (WIDTH * SCROLL_CHAR_HEIGHT);
var scroller_buffer: RenderBuffer = .{ .buffer = &scroller_pixels, .width = WIDTH, .height = SCROLL_CHAR_HEIGHT };

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    scroller_target: RenderTarget = undefined,
    logo: Background = undefined,
    logo_drawn: bool = false, // the logo plane never changes: drawn once
    scroller_y_pos: i16 = 0,
    scroller_y_dir: i16 = 1,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        zigos.setHBLHandler(handler_hbl);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        self.logo.init(fb.getRenderTarget(), logo_b, 0);
        self.logo_drawn = false;
        
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler);   

        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal1);    
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        scroller_pal = null; // entry 0 is not font_pal1's: the first line installs it

        @memset(&scroller_pixels, 0);
        self.scroller_target = .{ .render_buffer = &scroller_buffer };  

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
        fb.setFrameBufferHBLHandler(0, handler_scroller);   
        self.scroller_y_pos = 0;
        self.scroller_y_dir = 1;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();
        self.logo.update();

        self.frame_counter += 1;

        // scroller_period = ScrollerPeriods.threelines;
        switch (self.frame_counter) {
            60*0...(60*10) - 1 => scroller_period = ScrollerPeriods.threelines,
            60*10...(60*13) - 1 => scroller_period = ScrollerPeriods.big_font,
            60*13...(60*30) - 1 => scroller_period = ScrollerPeriods.threelines,
            60*30...(60*50) - 1 => scroller_period = ScrollerPeriods.big_font,
            60*50...(60*80) - 1 => scroller_period = ScrollerPeriods.interlaced_mirror,
            60*80...(60*106) - 1 => scroller_period = ScrollerPeriods.interlaced_big_font,
            60*106...(60*116) - 1 => scroller_period = ScrollerPeriods.inverted,
            60*116...(60*137) - 1 => scroller_period = ScrollerPeriods.interlaced_steam,
            60*137...(60*157) - 1 => scroller_period = ScrollerPeriods.inverted_mirror,
            else => self.frame_counter = 0
        }

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        if (!self.logo_drawn) self.logo.render();
        self.logo_drawn = true;

        // Letters as whole-row copies: the library Sprite walked every pixel with
        // a per-pixel clamp and divide (10,934 a frame). Word stores for the clear.
        @memset(&scroller_pixels, 0);
        letter_rows.draw(&self.scrolltext, &scroller_pixels, WIDTH, WIDTH, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT);

        // copy scrolltext to FB
        const fb = &zigos.lfbs[1];
        @memset(fb.fb[0 .. @as(u32, fb.fb_h) * fb.stride], 0);

        // The big fonts bounce on 0..56 lines.
        if (scroller_period == .big_font or scroller_period == .interlaced_big_font) {
            self.scroller_y_pos += self.scroller_y_dir;
            if (self.scroller_y_pos > 55) self.scroller_y_dir = -1;
            if (self.scroller_y_pos <= 0) self.scroller_y_dir = 1;
        }
        strip.draw(fb.fb, &scroller_pixels, scroller_period, self.scroller_y_pos);

        _ = elapsed_time;

    }
};
