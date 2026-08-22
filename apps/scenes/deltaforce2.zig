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
const RenderBuffer = @import("../zigos.zig").RenderBuffer;

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
const fonts_b = @embedFile("../assets/screens/df2/fonts.raw");
const SCROLL_TEXT = "               JINXSTER - CRACKED IN A WHOLE NIGHT BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP! THIS VERSION RUNS IN ANY PATH! THIS INTRO WAS DESIGNED, CREATED, AND PROGRAMMED BY CHAOS, INC. GREETINGS GO TO : 42-CREW (HEY MARTIN, STILL TRYING TO CRACK DUNGEON MASTER?), TEX (WE ARE WAITING FOR YOUR B.I.G. DEMO!!), CSS (WHERE ARE YOU?!), PHIL/UK, DIV D, MR. ATARI, KILLER, B.O.S.S., DMA (NOTHING HEARD OF YOU GUYS! YOU OK?), TSUNOO, HCC.  INTERNAL GREETINGS TO : JOE COOL, QUESTLORD, NEW MODE, GREEN BERET CRACKER, AND ALL THE OTHER MEMBERS OF THE UNION!  YEP, YOU GOT IT, WE'RE AT THE END OF THE SCROLL............ C YA!!   ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 30;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SCROLL_INTERSPACE = 3;

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df2/fonts_pal.dat"));
const rasterbars_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df2/rasterbars_pal.dat"));

// rasters
const scroll_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/df2/scrollrasters.dat"));
const rasterbars_b = @embedFile("../assets/screens/df2/rasterbars.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------


// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// fn handler_rasterbars(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {

//     fb.setPaletteEntry(0, rasters_b[col % 10]);

//     _ = zigos;
//     _ = line;
// }

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 40 and line < 240 ) {
        fb.setPaletteEntry(1, scroll_rasters_b[line - 40]);
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
    scroller_target: RenderTarget = undefined,
    scroller_pos_y: u16 = SCROLL_CHAR_HEIGHT-1,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
  
        // HBL Handler for the raster effect
        // fb.setFrameBufferHBLHandler(0, handler_rasterbars);   
        fb.setPalette(rasterbars_pal);

        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_scroller);        

        var buffer = [_]u8{0} ** (WIDTH * (SCROLL_CHAR_HEIGHT+2) * 2); 
        var render_buffer: RenderBuffer = .{ .buffer = &buffer, .width = WIDTH, .height = (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * 2};  
        self.scroller_target = .{ .render_buffer = &render_buffer };   
        self.scroller_pos_y = (SCROLL_CHAR_HEIGHT - 1);

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();

        self.frame_counter += 1;
        if (self.frame_counter == 10) self.frame_counter  = 0;

        self.scroller_pos_y -= 1;
        if(self.scroller_pos_y == 0) self.scroller_pos_y = (SCROLL_CHAR_HEIGHT + SCROLL_INTERSPACE - 1);
            
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        var fb = &zigos.lfbs[0];
        var i: u16 = 0;
        while(i < WIDTH*HEIGHT) : (i += 1) {
            fb.fb[i] = rasterbars_b[(self.frame_counter + i) % 10];
        }

        fb = &zigos.lfbs[1];
        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        // copy scrolltext another time
        i = 0;
        while(i < (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1) {
            self.scroller_target.render_buffer.buffer[i + ((SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i];
        }

        i = 0;
        const offset = self.scroller_pos_y * WIDTH;
        while(i < (WIDTH*(SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE))) : ( i += 1){
            fb.fb[i + (0 * (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i + offset];
            fb.fb[i + (1 * (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i + offset];
            fb.fb[i + (2 * (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i + offset];
            fb.fb[i + (3 * (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i + offset];
            fb.fb[i + (4 * (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i + offset];
            fb.fb[i + (5 * (SCROLL_CHAR_HEIGHT+SCROLL_INTERSPACE) * WIDTH)] = self.scroller_target.render_buffer.buffer[i + offset];
        }

        i = 0;
        var j: u16 = (6 * (SCROLL_CHAR_HEIGHT + SCROLL_INTERSPACE) * WIDTH);
        while(j < (WIDTH*HEIGHT)) : ( j += 1){
            fb.fb[j] = self.scroller_target.render_buffer.buffer[i + offset];
            i += 1;
        }        

        _ = elapsed_time;

    }
};
