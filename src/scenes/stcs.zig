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

const fonts_b = @embedFile("../assets/screens/stcs/font40x34_c1.raw");
const SCROLL_TEXT = "              PLEASE, READ ALL THIS SCROLL !!!           THE S.T.C.S. STRIKES BACK WITH THIS MEGA-NEWS CALLED                ";
const SCROLL_CHAR_WIDTH = 40; 
const SCROLL_CHAR_HEIGHT = 34;
const SCROLL_SPEED = 4;
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
var raster_index: u8 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 40+66 and line < 40+200) {
        fb.setPaletteEntry(0, rasters_b[line - 40 - 66]);
    } else {
        fb.setPaletteEntry(0, back_color);
    }

    _ = zigos;
    _ = col;
}

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {

    if(line > 40+SCROLL_TOP_POS) {
        fb.setPalette(font_pal1);
    }

    if(line > 40+SCROLL_TOP_POS+5+SCROLL_CHAR_HEIGHT) {
        fb.setPalette(font_pal2);
    }

    if(line > 40+SCROLL_TOP_POS+2*(5+SCROLL_CHAR_HEIGHT)) {
        fb.setPalette(font_pal3);
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
        fb.setFrameBufferHBLHandler(0, handler);   

        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal1);    
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, SCROLL_TOP_POS, null, null, null);
        fb.setFrameBufferHBLHandler(0, handler_scroller);   

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
        var i: u16 = SCROLL_TOP_POS * WIDTH;
        while(i < (SCROLL_TOP_POS * WIDTH) + (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1){
            const pal_entry = fb.fb[i];
            fb.fb[i + ((SCROLL_CHAR_HEIGHT+5) * WIDTH)] = pal_entry;
            fb.fb[i + ((SCROLL_CHAR_HEIGHT+SCROLL_CHAR_HEIGHT+10) * WIDTH)] = pal_entry;
        }

        _ = elapsed_time;

    }
};
