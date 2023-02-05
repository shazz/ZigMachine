// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const readI16Array = @import("../utils/loaders.zig").readI16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const RenderTarget = @import("../zigos.zig").RenderTarget;
const RenderBuffer = @import("../zigos.zig").RenderBuffer;
const Resolution = @import("../zigos.zig").Resolution;
const Color = @import("../zigos.zig").Color;

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Sprite = @import("../effects/sprite.zig").Sprite;
const Text = @import("../effects/text.zig").Text;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext
const fonts_b = @embedFile("../assets/screens/dbug/fonts_32x24.raw");
const SCROLL_TEXT = "JUST WHEN YOU THOUGHT WE WERE OUT...WE ARE STILL HERE! THIS MEGA INTRO WAS DONE BY !CUBE OF AGGRESSION, AND IT IS PROBABLY THE BIGGEST REASON YOU ARE SEEING THIS RELEASE AT ALL :P        GREETZ TO ALL THAT DESERVE IT...         LET'S WRAP.............      ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 24;
const SCROLL_SPEED = 1;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH / SCROLL_CHAR_WIDTH + 1;

// text
const text_fonts_b = @embedFile("../assets/screens/dbug/fonts_16x14.raw");
const TEXT_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/fonts_32x24_pal.dat"));
const text_font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/fonts_16x14_pal.dat"));
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/logo_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/rasters.dat"));

// logo
const  logo_b = @embedFile("../assets/screens/dbug/logo.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var start_raster_line: u16 = 0;
var off_buffer = [_]u8{0} ** (400 * 280); 

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {    


    // Open top border and use top buffer to fill the space
    if(line == 0 and col == 0) {

        var y: u16 = 0;
        while( y < 40) : ( y += 1) {
            var x: u16 = 0;
            while( x < WIDTH) : ( x += 1) {
                fb.fb[x + (y * WIDTH)] = off_buffer[x + (y * WIDTH) + (80 * y)];
            }
        }
        fb.setFrameBufferHBLHandler(40, handler_scroller);   
    }

    // Open top border and use top buffer to fill the space
    if(line == 0 and col == 40) {
        // Console.log("opening top border!", .{});
        zigos.setResolution(Resolution.truecolor);
        fb.setFrameBufferHBLHandler(0, handler_scroller);   
    }

    if(line == 40 and col == 0) {
        // render to FB the top-left part of the offscreen buffer
        var y: u32 = 0;
        while( y < HEIGHT) : ( y += 1) {
            var x: u32 = 0;
            const buf_offset: u32 = ((y + 40) * WIDTH) + (80 * (y + 40));
            const scr_offset: u32 = y * WIDTH;

            while( x < WIDTH) : ( x += 1) {
                fb.fb[x + scr_offset] = off_buffer[x + buf_offset];
            }
        }
    }

    if(line == 240 and col == 0) {
        var y: u32 = 0;
        while( y < 40) : ( y += 1) {
            var x: u32 = 0;
            const offscreen_offset: u32 = (240 * 400) + (y * WIDTH);

            while(x < WIDTH) : ( x += 1) {
                fb.fb[x + ( (y + 160) * WIDTH)] = off_buffer[x + offscreen_offset + (80 * y)];
            }
        }
        fb.setFrameBufferHBLHandler(40, handler_scroller); 
    }  

    // Open top border and use top buffer to fill the space
    if(line == 240 and col == 40) {
        // Console.log("opening low border!", .{});
        zigos.setResolution(Resolution.truecolor);
        fb.setFrameBufferHBLHandler(0, handler_scroller); 
    }    

    if (line > start_raster_line and line < start_raster_line + 192 ) {
        fb.setPaletteEntry(7, rasters_b[(line - start_raster_line)]);
    }

}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    scroller_target: RenderTarget = undefined,
    overscan_target: RenderTarget = undefined,
    text: Text = undefined,
    scroller_y: f32 = 0.0,
    bounce: i32 = 0,
    bounce_att: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);
        fb.setPaletteEntry(7, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });    

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_scroller);        

        // only a 50 pixels wide buffer is needed as it will be zoomed 8 times (320+80 / 8)
        var buffer = [_]u8{0} ** (50 * SCROLL_CHAR_HEIGHT); 
        var render_buffer: RenderBuffer = .{ .buffer = &buffer, .width = 50, .height = SCROLL_CHAR_HEIGHT };  
        self.scroller_target = .{ .render_buffer = &render_buffer };   

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
        self.scroller_y = 0.0;

        // big buffer to the siz of the overscan
        var overscan_render_buffer: RenderBuffer = .{ .buffer = &off_buffer, .width = 400, .height = 280 };  
        self.overscan_target = .{ .render_buffer = &overscan_render_buffer };   

        // copy logo palette starting at 100
        fb.setPaletteEntry(100, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(101, logo_pal[1]);
        fb.setPaletteEntry(102, logo_pal[2]);
        fb.setPaletteEntry(103, logo_pal[3]);
        self.logo.init(self.overscan_target, logo_b, 253, 38, WIDTH/2-126, 20, null, null);  
        self.bounce = 0;
        self.bounce_att = 1;

        // text
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(text_font_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });    
        self.text.init(fb.getRenderTarget(), text_fonts_b, TEXT_CHARS, 16, 14);

        Console.log("demo init done!", .{});


    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();
        self.logo.update(null, null, null, null);

        const f_sin: f32 = @fabs(@sin(self.scroller_y)) * 88.0; 
        start_raster_line = @floatToInt(u16, 88.0 - f_sin);
        // start_raster_line = 38;

        self.scroller_y += 0.04;

        // logo bounce
        var offset_y: i32 = 0;
        if(start_raster_line >= 86 and self.bounce == 0) self.bounce = 1;

        if(self.bounce > 0) {
            const fac: f32 = @intToFloat(f32, self.bounce);
            const f_attsin: f32 = 5 * (@sin(fac)/self.bounce_att);
            self.bounce += 1;
            self.bounce_att += 0.2;
            offset_y = @floatToInt(i32, f_attsin);

            if(self.bounce_att > 10) {
                self.bounce = 0;
                self.bounce_att = 1;
            }
        }
        self.logo.update(null, 20 + offset_y, null, null);

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        // draw the zoomed scrolltext on a overscan buffer
        self.overscan_target.clearFrameBuffer(0);
        const start_line: u32 = start_raster_line * 400;

        var char_row: u32  = 0;
        while(char_row < SCROLL_CHAR_HEIGHT) : ( char_row += 1) {
            
            const buffer_offset: u32 = char_row * self.scroller_target.render_buffer.width;

            var row: u32 = 0;
            while(row < 8) : ( row += 1) {
                const screen_offset: u32 = start_line + (row * 400) + (char_row * 8 * 400);

                var col: u32 = 0;
                while(col < 50) : ( col += 1){
                    const pal_entry = self.scroller_target.render_buffer.buffer[buffer_offset + col];
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 0] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 1] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 2] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 3] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 4] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 5] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 6] = pal_entry;
                    self.overscan_target.render_buffer.buffer[screen_offset + (8 * col) + 7] = pal_entry;
                }
            }
        }
        self.logo.render(100);

        self.render_text(32);

        _ = elapsed_time;
        _ = zigos;

    }

    fn render_text(self: *Demo, y_offset: u16) void {

        self.text.render("********************",0, y_offset +  0 * 14);
        self.text.render("*                  *",0, y_offset +  1 * 14);
        self.text.render("*    CODE, FONT    *",0, y_offset +  2 * 14);
        self.text.render("*   AND MUSIC BY   *",0, y_offset +  3 * 14);
        self.text.render("*   ------------   *",0, y_offset +  4 * 14);
        self.text.render("* !CUBE/AGGRESSION *",0, y_offset +  5 * 14);
        self.text.render("*                  *",0, y_offset +  6 * 14);
        self.text.render("*     LOGO BY      *",0, y_offset +  7 * 14);
        self.text.render("*     -------      *",0, y_offset +  8 * 14);
        self.text.render("*   RANDOM/DHFC    *",0, y_offset +  9 * 14);
        self.text.render("*                  *",0, y_offset + 10 * 14);
        self.text.render("********************",0, y_offset + 11 * 14);
    }
};


        // const start_line: u16 = start_raster_line * WIDTH;

        // var char_row: u16 = 0;
        // while(char_row < SCROLL_CHAR_HEIGHT) : ( char_row += 1) {
            
        //     // 5 is the 40 left overscan pixels
        //     const buffer_offset: u16 = 5 + (char_row * self.scroller_target.render_buffer.width);

        //     var row:u16 = 0;
        //     while(row < 8) : ( row += 1) {
        //         const screen_offset: u16 = start_line + (row * WIDTH) + (char_row * 8 * WIDTH);

        //         var col: u16 = 0;
        //         while(col < 40) : ( col += 1){
        //             const pal_entry = self.scroller_target.render_buffer.buffer[buffer_offset + col];
        //             fb.fb[screen_offset + (8 * col) + 0] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 1] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 2] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 3] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 4] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 5] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 6] = pal_entry;
        //             fb.fb[screen_offset + (8 * col) + 7] = pal_entry;
        //         }
        //     }
        // }