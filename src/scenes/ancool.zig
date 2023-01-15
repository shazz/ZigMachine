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

const Starfield = @import("../effects/starfield.zig").Starfield;
const StarfieldDirection = @import("../effects/starfield.zig").StarfieldDirection;

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Dots3D = @import("../effects/dots3d.zig").Dots3D;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext
const fonts_b = @embedFile("../assets/fonts/ancool_font_interlaced.raw");
const offset_table_b = readU16Array(@embedFile("../assets/screens/scrolltext/scroll_sin.dat"));
const SCROLL_TEXT = "    YO YO   -AN COOL- IS BACK TO BURN WITH A NEW CRACK........ AND THE NEW CRACK IS               THE GAMES......    THIS TIME -MEGA CRIBB- FROM -1 LIFE CREW- SITS BY MY SIDE AND EATS CANDY   THE INTRO IS MADE BY: -AN COOL- AND THE CRACKING IS MADE BY: -AN COOL- AND -MEGA CRIBB-          BELIVE IT OR NOT, THE MUSAXX IS MADE BY: -AN COOL-           THIS GAME IS THE BEST SPORT-GAME I'VE SEEN ON THE ATARI ST AND I HOPE YOU WILL HAVE A GREAT TIME PLAYING IT.          I'VE BEEN OF THE CRACKING MARKET FOR A WHILE, BUT IT'S BECAUSE OF THE NEW DEMO (SOWHAT) WE ARE CODING. THE DEMO WILL CONTAIN ABOUT 10 SCREENS AND ALMOST ALL IS GOOD (I THINK)...   YOU WILL SEE MORE 2D-OBJECTS AND MORE COMPLEX 2D-OBJECTS IN THE DEMO-LOADER. THE DEMO SHOULD HAVE BEEN RELEASED AT OUR COPYPARTY THE 3-6 AUG. BUT AS ALWAYS........  YEAH, YOU KNOW??????.........        A HELLO GOES TO NICK OF TCB (HE WORKS AS A SECRET AGENT FOR KREML NOW)  AND SNAKE THE  LITTLE YELLOW BIRD OF REPLICANTS.......        OK.  I THINK THAT THAT WAS ALL FOR THIS TIME.....................";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 16;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " !   '   -. 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const g_y_offset_table_b = readI16Array(@embedFile("../assets/screens/ancool/scroller_sin.dat"));

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/fonts/ancool_font.pal"));
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/ancool/rasters.dat"));

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u16 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

fn handler(fb: *LogicalFB, line: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 40 and line < 240 ) {
        fb.setPaletteEntry(0, rasters_b[(raster_index + line - 40) % 152]);
    }
    if (line > 240) {
        fb.setPaletteEntry(0, back_color);
    }
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    starfield: Starfield = undefined,
    scrolltext: Scrolltext = undefined,
    dots3D: Dots3D = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];

        fb = &zigos.lfbs[0];
        self.starfield.init(fb, WIDTH, HEIGHT, 3, StarfieldDirection.RIGHT, 0);

        // 2nd plane
        fb = &zigos.lfbs[1];
        self.dots3D.init(fb);

        // 3rd plane
        fb = &zigos.lfbs[2];
        fb.setPalette(font_pal);

        // HBL Handler
        fb.setFrameBufferHBLHandler(handler);        

        // table
        // var i: u16 = 0;
        // var y_offset_table_b: [WIDTH*2]i16 = undefined;
        // while (i < WIDTH*2) : (i += 1) {
        //     y_offset_table_b[i] = -@intCast(i16, i / 6);
        // }

        self.scrolltext.init(fb, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 
                             100, null, g_y_offset_table_b);
        // self.scrolltext.init(fb, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 
        //                      170, offset_table_b, y_offset_table_b);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {
        self.starfield.update();
        self.dots3D.update();

        self.scrolltext.update();

        if(raster_index < 150) {
            raster_index += 2;
        } else {
            raster_index = 0;
        }

        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {
        self.starfield.render();

        self.dots3D.fb.clearFrameBuffer(0);
        self.dots3D.render();

        self.scrolltext.fb.clearFrameBuffer(1);
        self.scrolltext.render();

        _ = zigos;
    }
};
