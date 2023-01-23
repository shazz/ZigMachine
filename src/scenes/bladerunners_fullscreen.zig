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
const RenderTarget = @import("../zigos.zig").RenderTarget;
const Resolution = @import("../zigos.zig").Resolution;



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
const fonts_b = @embedFile("../assets/screens/bladerunners/fonts_pal.raw");
const SCROLL_TEXT = "      WELCOME TO 'DUNGEON MASTER' -- CRACKED BY THE cdefghijkl -- THIS GAME IS CRACKED FOR  THE BLADE RUNNERS  - THE ULTIMATE CRACKER CREW...HELLO BOSS,TEX,CSS,TNT-CREW,MMC,BXC,TSUNOO,1001-CREW,AND OF COURSE YOU......DUNGEON MASTER WAS A VERY GOOD PROTECTED GAME THAT TOOK A LONG TIME TO CRACK. SO IF YOU ARE REQUESTED TO PUT IN THE DUNGEON MASTER DISK JUST IGNORE THAT MESSAGE AND CONTINUE (PRESSING THE RETURN KEY) YOUR GAME...THANKS TO MMC FOR THE ORIGINAL THAT WAS AFTERWARDS NEARLY UNREADABLE! TO CHANGE THE TUNE TOGGLE WITH F1/F2 SO YOU WILL LISTEN TO BOTH OF THE RAMPAGE MUSIC PIECES AGAIN COMPOSED BY WHITTIE-BABY!...";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 32;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]ˆ_`abcdefghijklmnopqrstuvwxyz";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/bladerunners/fonts_pal.dat"));

// rasters
const font_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/bladerunners/raster_font_pal.dat"));
const back_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/bladerunners/raster_back_pal.dat"));


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u8 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_hbl(zigos: *ZigOS, line: u16) void {

    if(line >= 0 and line < 240) {
        zigos.setBackgroundColor(back_rasters_b[(line + 12 + raster_index) % 255]);
    }
    else {
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    }        
}


fn handler_back(fb: *LogicalFB, zigos: *ZigOS, line: u16) void {

    if(line >= 0 and line < 240) {
        fb.setPaletteEntry(0, back_rasters_b[(line - 40 + raster_index) % 255]);
    }

    _ = zigos;
}

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };


    if(line == 0) {
        // Console.log("opening the top border", .{});
        zigos.setResolution(Resolution.truecolor);
    }

    if(line == 240) {
        // Console.log("opening the bottom border", .{});
        zigos.setResolution(Resolution.planes);
    }    

    if (line > 0 and line < 240 ) {
        fb.setPaletteEntry(1, font_rasters_b[(line - 40) % 200]);
    }
    if (line == 240) {
        fb.setPaletteEntry(1, back_color);
    }

    // _ = zigos;
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Background = undefined,
    offset_table: [320]u16 = undefined,
    scroller_offset: u16 = 0,
    scroller_target: RenderTarget = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
  
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(handler_back); 
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(handler_scroller);      
        zigos.setHBLHandler(handler_hbl);     

        var i: usize = 0;
        var counter : f32 = 0;
        while(i < 320) : ( i += 1) {
            const f_sin: f32 = @fabs(@sin(counter)) * 14; 
            self.offset_table[i] = @floatToInt(u16, f_sin);
            counter += 0.04;
        }

        var buffer = [_]u8{0} ** (WIDTH * SCROLL_CHAR_HEIGHT);
        self.scroller_target = .{ .buffer = &buffer };

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null);
        self.scroller_offset = 0;
        
        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();

        self.frame_counter += 1;
        if (self.frame_counter == 2) {
            raster_index += 1;
            self.frame_counter = 0;
        }

        self.scroller_offset += 1;
        if(self.scroller_offset == self.offset_table.len) self.scroller_offset = 0;

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        var fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);
        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        // copy scrolltext 7 times
        var one_row: u16 = 0;
        const sine_offset: u16 = self.offset_table[self.scroller_offset];
        var row_height: u16 = WIDTH * (SCROLL_CHAR_HEIGHT - sine_offset);

        while(one_row < row_height) : ( one_row += 1) {
            fb.fb[one_row] = self.scroller_target.buffer[one_row + (WIDTH * sine_offset)];
        }

        var i: u16 = 0;
        while(i < (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1) {
            
            fb.fb[i + (( 32 - sine_offset ) * WIDTH)] = self.scroller_target.buffer[i];
            fb.fb[i + (( 64 - sine_offset ) * WIDTH)] = self.scroller_target.buffer[i];
            fb.fb[i + (( 96 - sine_offset ) * WIDTH)] = self.scroller_target.buffer[i];
            fb.fb[i + (( 128 - sine_offset ) * WIDTH)] = self.scroller_target.buffer[i];
            fb.fb[i + (( 160 - sine_offset ) * WIDTH)] = self.scroller_target.buffer[i];
        }

        one_row = 0;
        row_height = WIDTH * @min(32, 200 - (192 - sine_offset));
        while(one_row < row_height) : ( one_row += 1) {
            fb.fb[one_row + (( 192 - sine_offset ) * WIDTH)] = self.scroller_target.buffer[one_row];
        }

        _ = elapsed_time;

    }
};
