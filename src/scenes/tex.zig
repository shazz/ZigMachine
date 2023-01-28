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
const Bobs = @import("../effects/bobs.zig").Bobs;
const Starfield = @import("../effects/starfield.zig").Starfield;
const Sprite = @import("../effects/sprite.zig").Sprite;
const StarfieldDirection = @import("../effects/starfield.zig").StarfieldDirection;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

const NB_STARS = 100;

// scrolltext
pub const NB_FONTS: u8 = WIDTH/SCROLL_CHAR_WIDTH + 1;
const fonts_b = @embedFile("../assets/screens/the_union/fonts_pal.raw");
const SCROLL_TEXT = "             THE EXCEPTIONS PROUDLY PRESENT THIS NEW GAME CRACKED BY HOWDY FROM THE EXCEPTIONS MEMBER OF THE UNION     LET WRAP      ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 17;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SCROLL_POS: u16 = 142;
const BACK_POS: u16 = 200-87;

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/the_union/logo_pal.dat"));
const back_pal = convertU8ArraytoColors(@embedFile("../assets/screens/the_union/back_pal.dat"));
const blue_back_pal = convertU8ArraytoColors(@embedFile("../assets/screens/the_union/blue_back_pal.dat"));

// logo
const logo_b = @embedFile("../assets/screens/the_union/logo.raw");
const back_b = @embedFile("../assets/screens/the_union/back.raw");

// bob
const bob_h_b = @embedFile("../assets/screens/the_union/h.raw");
const bob_o_b = @embedFile("../assets/screens/the_union/o.raw");
const bob_w_b = @embedFile("../assets/screens/the_union/w.raw");
const bob_d_b = @embedFile("../assets/screens/the_union/d.raw");
const bob_y_b = @embedFile("../assets/screens/the_union/y.raw");
const bob_delta_b = @embedFile("../assets/screens/the_union/delta.raw");
const NB_BOBS = 11;
const bobs_images: [NB_BOBS][]const u8 = [_][]const u8{ bob_delta_b, bob_delta_b, bob_delta_b, bob_h_b, bob_o_b, bob_w_b, bob_d_b, bob_y_b, bob_delta_b, bob_delta_b, bob_delta_b };

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    back: Sprite = undefined,
    starfield: Starfield(NB_STARS) = undefined,
    bobs: Bobs(NB_BOBS) = undefined,
    bobs_pos: [NB_BOBS]f32 = undefined,
    logo_sinx: f32 = 0,
    logo_inc: f32 = 0,   

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        self.starfield = Starfield(NB_STARS).init(fb.getRenderTarget(), WIDTH, 95, 0, 1, 3, StarfieldDirection.LEFT);

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(2, Color{ .r = 0xE0, .g = 0xE0, .b = 0xE0, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;         
        fb.setPalette(logo_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.logo.init(fb.getRenderTarget(), logo_b, 208, 97, WIDTH/2-104, 0, null, null);      

        var i: usize = 0;
        while (i < NB_BOBS) : (i += 1) {
            self.bobs_pos[i] = 0.3*(@intToFloat(f32, i+1));
        }
        self.bobs = Bobs(NB_BOBS).init(fb.getRenderTarget(), bobs_images, 16, 8);



        // 3rd plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;           
        fb.setPalette(back_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.back.init(fb.getRenderTarget(), back_b, 320, 87, 0, BACK_POS, null, null);    
   
        // 4th plane
        fb = &zigos.lfbs[3];
        fb.is_enabled = true;           
        fb.setPalette(blue_back_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, SCROLL_POS, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.update();
        self.scrolltext.update();

        self.logo_sinx += 0.13;
        self.logo_inc += 0.008;

	    // logo.draw(mycanvas,320 + Math.sin(logosinx)*(100*Math.sin(logoInc)),194/2);
        var x_pos: f32 = @sin(self.logo_sinx) * (50 * @sin(self.logo_inc));
        self.logo.update(52 + @floatToInt(i16, x_pos), null, null, null);

        var i: usize = 0;
        while (i < NB_BOBS) : (i += 1) {

            const x_idx: f32 = 152 + 153 * @sin(self.bobs_pos[i]);
            const y_idx: f32 = 43 + 42 * @cos(self.bobs_pos[i]*1.5);
            const x: i16 = @floatToInt(i16, x_idx);
            const y: i16 = @floatToInt(i16, y_idx);
            self.bobs_pos[i] += 0.04;            

            self.bobs.update(i, x, y);
        }

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.target.clearFrameBuffer(0);
        self.starfield.render();

        self.bobs.target.clearFrameBuffer(0);
        self.logo.render();
        self.bobs.render();

        self.back.render();

        var fb = &zigos.lfbs[3];
        self.scrolltext.target.clearFrameBuffer(0);
        self.scrolltext.render();     


        var i: usize = SCROLL_POS * WIDTH;
        var tx: usize = (SCROLL_POS - BACK_POS) * WIDTH;
        while(i < (SCROLL_POS * WIDTH) + (WIDTH * SCROLL_CHAR_HEIGHT)) : ( i += 1) {
            if(fb.fb[i] == 1) {
                fb.fb[i] =  back_b[tx];
            }
            tx += 1;
        }           

        _ = elapsed_time;

    }
};
