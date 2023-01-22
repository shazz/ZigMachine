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
const Color = @import("../zigos.zig").Color;

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Sprite = @import("../effects/sprite.zig").Sprite;
const Background = @import("../effects/background.zig").Background;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext

const fonts_b = @embedFile("../assets/screens/ics/font_noics_pal.raw");
const SCROLL_TEXT = "    ICS PRESENTS YOU:         BUMPY'S     GAME CRACKED BY THE THREAT        ORIGINAL BY SLASH OF FRANCE       THIS INTRO WAS CODED, DESIGNED FOR I.C.S. BY  -EL PISTOLERO-..... (MANY THANKS!)     JUST AFTER THIS LITTLE INTRO YOU CAN READ A MESSAGE SENT TO SLASH BY SLEDGE, I THINK YOU'LL BE SURPRISED...           I WANT TO SAID A BIG HI TO  'NUKE' OUR NEW CRACKER, HE LIVES IN FRANCE LIKE A LOT OF MEMBERS OF ICS.      BIG HELLO TO SKINHEAD FROM GERMANY WHO GIVE US VERY HOT ORIGINALS (LIKE STONE AGE).      BIG HI TO SLASH AND BELGARION WHO ARE VERY GOOD/COOL GUYS!!!      AND OF COURSE I DON'T FORGET MR.FLY.        GREETINGS TO: SCSI, CYNIX, POMPEY PIRATES, DANNY FROM SINGAPORE, FUZION, THE REPLICANTS, AND YOU, IF YOU WANT!!!        WE LOOOKING FOR SUPPLIERS ALL OVER THE WORLD, IF YOU ARE INTRESTED WRITE TO THE P.O. BOX OR CALL ONE OF OUR BOARD.       THIS ALL FOR THIS TIME, SEE YOU SOON....              ";
const SCROLL_CHAR_WIDTH = 16; 
const SCROLL_CHAR_HEIGHT = 16;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH / SCROLL_CHAR_WIDTH + 1;

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/ics_logo_pal.dat"));
const grid_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/grid_large_pal.dat"));
// const grid_unit_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/grid_unit_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/ics/raster_pal.dat"));

// logo
const logo_b = @embedFile("../assets/screens/ics/ics_logo.raw");
const grid_b = @embedFile("../assets/screens/ics/grid_large.raw");


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u8 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_scroller(fb: *LogicalFB, line: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 40 and line < 165+40 ) {
        fb.setPaletteEntry(1, rasters_b[(line - 40)]);
    }
    if (line == 165+40) {
        fb.setPaletteEntry(1, back_color);
    }
}

pub const Demo = struct {
  
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    grid: Sprite = undefined,
    scroller_target: RenderTarget = undefined,
    sin_counter: f32 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(handler_scroller);        

        var buffer = [_]u8{0} ** (WIDTH * (HEIGHT-30));
        self.scroller_target = .{ .buffer = &buffer };
        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 1, null, null);

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 

        // set oversized grid
        fb.setPalette(grid_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });            
        self.grid.init(fb.getRenderTarget(), grid_b, 384, 288, 0, 0, false, null); 

        // third plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true; 

        fb.setPalette(logo_pal);
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });      

        self.logo.init(fb.getRenderTarget(), logo_b, 137, 31, WIDTH/2-68, HEIGHT-29, false, null); 
     
        fb.clearFrameBuffer(255);
        var i = (WIDTH*(HEIGHT-37));
        while(i < (200*WIDTH)) : ( i+= 1) {
            fb.fb[i] = 0;
        }

        self.sin_counter = 0;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();
        self.logo.update(null, null, null);

        var f_sin: f32 = @sin(-self.sin_counter) * 32 * 4; 
        var f_cos: f32 = @cos(-self.sin_counter) * 32 * 4;
        const delta_x = -32 + @mod(@floatToInt(i16, f_sin), 32);
        const delta_y = -32 + @mod(@floatToInt(i16, f_cos), 32);

        self.grid.update(delta_x, delta_y, null);

        self.sin_counter += 0.040;
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // clear the render target
        self.scroller_target.clearFrameBuffer(0);

        self.scrolltext.render();

        // copy scrolltext 9 times in the rendertarget
        var i: u16 = 0;
        while(i < (WIDTH*SCROLL_CHAR_HEIGHT)) : ( i += 1){
            self.scroller_target.buffer[i + (16*1 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*2 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*3 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*4 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*5 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*6 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*7 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*8 * WIDTH)] = self.scroller_target.buffer[i];
            self.scroller_target.buffer[i + (16*9 * WIDTH)] = self.scroller_target.buffer[i];
        }

        // copy the rendertarget to the fb
        var fb = &zigos.lfbs[0];
        i = 0;
        while(i < self.scroller_target.buffer.len) : (i += 1) {
            fb.fb[i] = self.scroller_target.buffer[i];
        }

        self.grid.target.clearFrameBuffer(0);
        self.grid.render();

        self.logo.render();        
  
        // _ = zigos;
        // _ = self;
        _ = elapsed_time;

    } 
};
