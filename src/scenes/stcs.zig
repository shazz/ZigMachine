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
const ScrollerPeriods = enum { threelines, big_font, interlaced_mirror, interlaced_big_font, inverted, interlaced_steam, inverted_mirror };
var scroller_period: ScrollerPeriods = .threelines;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_hbl(zigos: *ZigOS, line: u16) void {

    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 40+66 and line < 40+200) {
        zigos.setBackgroundColor(rasters_b[line - 40 - 66]);
    } else {
        zigos.setBackgroundColor(back_color);
    }      
}


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

    switch(scroller_period) {

        .threelines => {
            switch(line - 40) {
                84...84 + SCROLL_CHAR_HEIGHT + 5  => fb.setPalette(font_pal1),
                84 + SCROLL_CHAR_HEIGHT + 5 + 1...84 + 2*(SCROLL_CHAR_HEIGHT + 5)   => fb.setPalette(font_pal2),
                84 + 2*(SCROLL_CHAR_HEIGHT + 5) + 1...200 => fb.setPalette(font_pal3),
                else => fb.setPalette(font_pal1)
            }
        },
        .inverted_mirror => {
            switch(line - 40) {
                84...117 => fb.setPalette(font_pal1),
                118...150 => fb.setPalette(font_pal2),
                151...200 => fb.setPalette(font_pal3),
                else => fb.setPalette(font_pal1)
            }
        },
        .inverted => {
            switch(line - 40) {
                84...140 => fb.setPalette(font_pal1),
                141...200 => fb.setPalette(font_pal2),
                else => fb.setPalette(font_pal1),
            }
        },
        else => fb.setPalette(font_pal1)
    }        

    _ = zigos;
    _ = col;
}



pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    scroller_target: RenderTarget = undefined,
    logo: Background = undefined,
    scroller_y_pos: i16 = 0,
    scroller_y_dir: i16 = 1,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        zigos.setHBLHandler(handler_hbl);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        self.logo.init(fb.getRenderTarget(), logo_b, 0);        
        
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler);   

        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal1);    
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        var buffer = [_]u8{0} ** (WIDTH * SCROLL_CHAR_HEIGHT);
        var render_buffer: RenderBuffer = .{ .buffer = &buffer, .width = WIDTH, .height = SCROLL_CHAR_HEIGHT };   
        self.scroller_target = .{ .render_buffer = &render_buffer };  

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

        self.logo.render();

        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        // copy scrolltext to FB
        var fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);

        if(scroller_period == ScrollerPeriods.threelines) {

            const top_pos: u16 = SCROLL_TOP_POS*WIDTH;
            var i: u16 = 0;
            while(i < (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1){
                const pal_entry = self.scroller_target.render_buffer.buffer[i];
                fb.fb[top_pos + i] = pal_entry;
                fb.fb[top_pos + i + ((SCROLL_CHAR_HEIGHT+SCROLL_CHAR_HEIGHT+10) * WIDTH)] = pal_entry;            
                fb.fb[top_pos + i + ((SCROLL_CHAR_HEIGHT+5) * WIDTH)] = pal_entry;
                fb.fb[top_pos + i + ((SCROLL_CHAR_HEIGHT+SCROLL_CHAR_HEIGHT+10) * WIDTH)] = pal_entry;
            }
        }


        if( scroller_period == ScrollerPeriods.big_font ) {
        
            // big font
            self.scroller_y_pos += self.scroller_y_dir ;
            if(self.scroller_y_pos > 55) self.scroller_y_dir = -1;
            if(self.scroller_y_pos <= 0) self.scroller_y_dir = 1;

            const top_pos: u16 = (78 + @intCast(u16, self.scroller_y_pos))*WIDTH;
            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1) {
                var x: u16 = 0;
                while(x < WIDTH) : (x += 1) { 
                    const pos = x + (y * WIDTH);
                    const pal_entry = self.scroller_target.render_buffer.buffer[pos];

                    // double height font and sinus incr/decr on 16 pixels
                    fb.fb[x + top_pos + ((2*y) * WIDTH)] = pal_entry;
                    fb.fb[x + top_pos + ((2*y+1) * WIDTH)] = pal_entry;
                }
            }
        }

        if( scroller_period == ScrollerPeriods.interlaced_big_font) {

            // big interlaced font
            self.scroller_y_pos += self.scroller_y_dir ;
            if(self.scroller_y_pos > 55) self.scroller_y_dir = -1;
            if(self.scroller_y_pos <= 0) self.scroller_y_dir = 1;

            const top_pos: u16 = (78 + @intCast(u16, self.scroller_y_pos))*WIDTH;
            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1) {
                var x: u16 = 0;
                while(x < WIDTH) : (x += 1) { 
                    const pos = x + (y * WIDTH);
                    const pal_entry = self.scroller_target.render_buffer.buffer[pos];
                    fb.fb[x + top_pos + ((2*y) * WIDTH)] = pal_entry;
                }
            }     

        }

        if( scroller_period == ScrollerPeriods.interlaced_mirror) {

            // big interlaced font mirrored
            const top_pos: u16 = 88*WIDTH;
            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1) {
                var x: u16 = 0;
                while(x < WIDTH) : (x += 1) { 
                    const pos = x + (y * WIDTH);
                    const pal_entry = self.scroller_target.render_buffer.buffer[pos];

                    // normal line
                    fb.fb[x + top_pos + (y * WIDTH) - ((x / 16) * WIDTH)] = pal_entry;

                    // mirrored interlaced
                    fb.fb[x + top_pos + (((SCROLL_CHAR_HEIGHT)+5)*WIDTH) + (((2*SCROLL_CHAR_HEIGHT)-(2*y)) * WIDTH) - ((x / 16) * WIDTH)] = pal_entry;
                }
            }     
        }

        if( scroller_period == ScrollerPeriods.interlaced_steam) {

            // big interlaced font mirrored
            const top_pos: u16 = 164*WIDTH;
            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1) {
                var x: u16 = 0;
                while(x < WIDTH) : (x += 1) { 
                    const pos = x + (y * WIDTH);
                    const pal_entry = self.scroller_target.render_buffer.buffer[pos];

                    // normal line
                    fb.fb[x + top_pos + (y * WIDTH)] = pal_entry;

                    // mirrored interlaced
                    fb.fb[x + (76*WIDTH) + ((2*y) * WIDTH) + ((x / 16) * 2 * WIDTH)] = pal_entry;
                }
            }     
        }        

        if( scroller_period == ScrollerPeriods.inverted) {

            const top_pos: u16 = 86*WIDTH;
            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1) {
                var x: u16 = 0;
                while(x < WIDTH) : (x += 1) { 
                    const pos = x + (y * WIDTH);
                    const pal_entry = self.scroller_target.render_buffer.buffer[pos];
                    // top line with 16 pixel increment
                    fb.fb[x + top_pos + (y * WIDTH) + ((x / 16) * WIDTH)] = pal_entry;

                    // bottom line reversed with 16 pixel decrement
                    fb.fb[x + (156*WIDTH) + ((SCROLL_CHAR_HEIGHT-y) * WIDTH) - ((x / 16) * WIDTH)] = pal_entry;
                }
            }  
        }

        if(scroller_period == ScrollerPeriods.inverted_mirror) {

            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1) {
                var x: u16 = 0;
                while(x < WIDTH) : (x += 1) { 
                    const pos = x + (y * WIDTH);
                    const pal_entry = self.scroller_target.render_buffer.buffer[pos];

                    // 1st line 16 pixel decrement then increment
                    if(x < 160) {
                        fb.fb[x + (90*WIDTH) + (y * WIDTH) - ((x / 16) * WIDTH)] = pal_entry;
                    } else {
                        fb.fb[x + (80*WIDTH) + (y * WIDTH) + (((x-160) / 16) * WIDTH)] = pal_entry;
                    }

                    // 2nd line inverted 16 pixel increment then decrement
                    if(x < 160) {
                        fb.fb[x + (110*WIDTH) + ((SCROLL_CHAR_HEIGHT-y) * WIDTH) + ((x / 16) * WIDTH)] = pal_entry;
                    } else {
                        fb.fb[x + (120*WIDTH) + ((SCROLL_CHAR_HEIGHT-y) * WIDTH) - (((x-160) / 16) * WIDTH)] = pal_entry;
                    }                    

                    // last line normal
                    fb.fb[x + (160*WIDTH) + (y * WIDTH)] = pal_entry;
                }
            }  
        }            

        _ = elapsed_time;

    }
};
