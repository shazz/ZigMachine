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

const Scrolltext = zg.Scrolltext;

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
// The highest line any period writes on plane 1 (interlaced_mirror, group 19: 88 - 19).
const BAND_TOP: i16 = 69;

// The logo (stcs_logo.zig) shares plane 1 with the scroller: rows 0..72.
const logo = @import("stcs_logo.zig");


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
const strip = @import("stcs_strip.zig");
const scratch = @import("stcs_scratch.zig");
const hbl = @import("stcs_hbl.zig"); // the rasters and the band palettes
const ScrollerPeriods = strip.Period;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// The scroller's source strips live in the two disabled planes (stcs_scratch.zig).
var chisel: zg.Blitter = .{};
var strips = scratch.scratch(fonts_b);

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    scroller_target: RenderTarget = undefined,
    logo_drawn: bool = false, // the logo's rows above the band never change: drawn once
    scroller_y_pos: i16 = 0,
    scroller_y_dir: i16 = 1,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        hbl.reset();
        zigos.setHBLHandler(hbl.global);

        // The logo used to be plane 0, under the scroller's plane 1. It is now
        // drawn INTO plane 1 (its colours moved to 17..31, stcs_logo.zig) and
        // plane 0 stays disabled: FRESCO composites one plane, not two, and the
        // composed picture is the same (apps/stcs_headless.mjs).
        zigos.lfbs[0].is_enabled = false;
        self.logo_drawn = false;

        const fb: *LogicalFB = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(hbl.font_pal1);    
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        for (1..logo.COLORS) |i| fb.setPaletteEntry(@intCast(logo.BASE + i), hbl.logo_pal[i]);

        self.scroller_target = fb.getRenderTarget(); // never drawn through: the letters are blitted
        chisel.init();
        strips.init(&chisel, zigos);

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
        fb.setFrameBufferHBLHandler(0, hbl.plane); // the band palettes + the logo's raster (entry 0)
        self.scroller_y_pos = 0;
        self.scroller_y_dir = 1;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();

        self.frame_counter += 1;

        // hbl.period = ScrollerPeriods.threelines;
        switch (self.frame_counter) {
            60*0...(60*10) - 1 => hbl.period = ScrollerPeriods.threelines,
            60*10...(60*13) - 1 => hbl.period = ScrollerPeriods.big_font,
            60*13...(60*30) - 1 => hbl.period = ScrollerPeriods.threelines,
            60*30...(60*50) - 1 => hbl.period = ScrollerPeriods.big_font,
            60*50...(60*80) - 1 => hbl.period = ScrollerPeriods.interlaced_mirror,
            60*80...(60*106) - 1 => hbl.period = ScrollerPeriods.interlaced_big_font,
            60*106...(60*116) - 1 => hbl.period = ScrollerPeriods.inverted,
            60*116...(60*137) - 1 => hbl.period = ScrollerPeriods.interlaced_steam,
            60*137...(60*157) - 1 => hbl.period = ScrollerPeriods.inverted_mirror,
            else => self.frame_counter = 0
        }

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // CHISEL only: the logo's rows above the band once; then each frame the
        // band the strips can reach (lines 69..199) back to what is under the
        // scroller (the logo's last rows, 69..72, then 0), the source strips this
        // period copies from rebuilt, and copied in its shape (stcs_strip.zig).
        const fb = &zigos.lfbs[1];
        chisel.init();
        if (!self.logo_drawn) logo.drawTop(&chisel, fb, BAND_TOP);
        self.logo_drawn = true;
        logo.restoreBand(&chisel, fb, BAND_TOP);
        for (strip.needs(hbl.period)) |k| strips.build(&chisel, &self.scrolltext, k);

        // The big fonts bounce on 0..56 lines.
        if (hbl.period == .big_font or hbl.period == .interlaced_big_font) {
            self.scroller_y_pos += self.scroller_y_dir;
            if (self.scroller_y_pos > 55) self.scroller_y_dir = -1;
            if (self.scroller_y_pos <= 0) self.scroller_y_dir = 1;
        }
        strip.draw(&chisel, fb, &strips, hbl.period, self.scroller_y_pos);

        _ = elapsed_time;

    }
};
