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
// David Whittaker, "Rampage" (1988).
const MUSIC = "rampage.sndh";

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

    if(line >= 40 and line < 240) {
        zigos.setBackgroundColor(back_rasters_b[(line + 12 + raster_index) % 255]);
    }
    else {
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    }        
}


fn handler_back(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {

    // Per-plane HBL: sealed machine fires on LOGICAL lines 0..199 (was physical 40..239), so drop the +40.
    if(line < 200) {
        fb.setPaletteEntry(0, back_rasters_b[(line + raster_index) % 255]);
    }

    _ = zigos;
    _ = col;
}

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Per-plane HBL: sealed machine fires on LOGICAL lines 0..199 (was physical 40..239), so drop the +40.
    if (line < 200 ) {
        fb.setPaletteEntry(1, font_rasters_b[line % 200]);
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
    offset_table: [320]u16 = undefined,
    scroller_offset: u16 = 0,
    scroller_target: RenderTarget = undefined,
    // Backing store for scroller_target's render_buffer view. Was previously a
    // stack-local in init() (dangling pointer once init() returned) — must live
    // as long as the Demo instance, so it is a struct field now.
    scroller_buffer: [WIDTH * SCROLL_CHAR_HEIGHT]u8 = undefined,
    scroller_render_buffer: RenderBuffer = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
  
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_back); 
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_scroller);      
        zigos.setHBLHandler(handler_hbl);     

        var i: usize = 0;
        var counter : f32 = 0;
        while(i < 320) : ( i += 1) {
            const f_sin: f32 = @abs(@sin(counter)) * 14; 
            self.offset_table[i] = @as(u16, @intFromFloat(f_sin));
            counter += 0.04;
        }

        self.scroller_buffer = [_]u8{0} ** (WIDTH * SCROLL_CHAR_HEIGHT);
        self.scroller_render_buffer = .{ .buffer = &self.scroller_buffer, .width = WIDTH, .height = SCROLL_CHAR_HEIGHT };
        self.scroller_target = .{ .render_buffer = &self.scroller_render_buffer };

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
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
            fb.fb[one_row] = self.scroller_target.render_buffer.buffer[one_row + (WIDTH * sine_offset)];
        }

        var i: u16 = 0;
        while(i < (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1) {
            
            fb.fb[i + (( 32 - sine_offset ) * WIDTH)] = self.scroller_target.render_buffer.buffer[i];
            fb.fb[i + (( 64 - sine_offset ) * WIDTH)] = self.scroller_target.render_buffer.buffer[i];
            fb.fb[i + (( 96 - sine_offset ) * WIDTH)] = self.scroller_target.render_buffer.buffer[i];
            fb.fb[i + (( 128 - sine_offset ) * WIDTH)] = self.scroller_target.render_buffer.buffer[i];
            fb.fb[i + (( 160 - sine_offset ) * WIDTH)] = self.scroller_target.render_buffer.buffer[i];
        }

        one_row = 0;
        row_height = WIDTH * @min(32, 200 - (192 - sine_offset));
        while(one_row < row_height) : ( one_row += 1) {
            fb.fb[one_row + (( 192 - sine_offset ) * WIDTH)] = self.scroller_target.render_buffer.buffer[one_row];
        }

        _ = elapsed_time;

    }
};
