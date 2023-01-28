// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const readI16Array = @import("../utils/loaders.zig").readI16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Background = @import("../effects/background.zig").Background;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext
pub const NB_FONTS: u8 = 11;
const fonts_b = @embedFile("../assets/screens/df/fonts2_pal.raw");
const SCROLL_TEXT = "               TESTDRIVE WAS CRACKED BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP.    THIS INTRO WAS CODED BY CHAOS, INC., TOO.  FIRST OF ALL I WANT TO THANK GUIDO OF THE MAD MAX COPORATION FOR THE ORIGINAL!      GREETINGS TO: NEW-MODE, ABC, QUESTLORD, JOE COOL, GREEN BERET CRACKERS, PSYCHO.     ALSO GREETINGS TO: 42-CREW, TNT-CREW, TNT, COPY SERVICE STUTTGART, TEX, CERTAINLY MAD MAX COPORATION AND, LAST BUT NOT LEAST, ACCOLADE!      WAIT FOR OUR NEXT INTRO, WHICH WILL INCLUDE SOME DIGISOUNDS.     HEY ACCOLADE, CAN'T YOU MAKE A BETTER SOUND? IT'S REALLY AWFUL AND BORING! SOME DIGISOUND, WHILE  THE CAR IS CRASHING?    WHY NOT?      THAT'S IT FOR TODAY.....   CHAOS, INC.                            WHAT'S UP FOLKS?                        YOU WAIT FOR THE END?           HERE IT IS!   ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 30;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df/fonts2_pal.dat"));
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df/top_logo_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/df/rasters_pal.dat"));
const top_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/df/top_raster_pal.dat"));

// logo
const logo_b = @embedFile("../assets/screens/df/top_logo.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u8 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_logo(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    const current_color: Color = top_rasters_b[raster_index];

    if (line > 40+5 and line < 40+19 ) {
        fb.setPaletteEntry(255, current_color);
    }
    if (line == 60) {
        fb.setPaletteEntry(255, back_color);
    }

    _ = zigos;
    _ = col;
}

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 52+40 and line < 240 ) {
        fb.setPaletteEntry(1, rasters_b[(line - 40 - 52)]);
    }
    if (line == 240) {
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

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        self.logo.init(fb.getRenderTarget(), logo_b);        
        
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_logo);   


        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);

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

        self.logo.render();

        var fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);
        self.scrolltext.render();

        // copy scrolltext 3 times
        var i: u16 = 52 * WIDTH;
        while(i < (52 * WIDTH) + (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1){
            fb.fb[i + (39 * WIDTH)] = fb.fb[i];
            fb.fb[i + (78 * WIDTH)] = fb.fb[i];
            fb.fb[i + (117 * WIDTH)] = fb.fb[i];
        }

        _ = elapsed_time;

    }
};
