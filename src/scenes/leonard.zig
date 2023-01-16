// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const math = std.math;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Bobs = @import("../effects/bobs.zig").Bobs;
const Background = @import("../effects/background.zig").Background;
const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;
const NB_BOBS = @import("../effects/bobs.zig").NB_BOBS;

const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

pub const PHYSICAL_WIDTH: u16 = @import("../zigos.zig").PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = @import("../zigos.zig").PHYSICAL_HEIGHT;

pub const NB_FONTS: u8 = 320/6 + 1;
const fonts_b = @embedFile("../assets/screens/leonard/font_pal.raw");
const SCROLL_TEXT = "                                                                                            HI EVERYBODY ! ULTRA OPTIMISATION RULES, EVEN FOR STUPID RECORD ! I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO !  I TOTALLY REWRITE MY PC DATABUILDER TO IMPLEMENT NEW STUFF. THEN, I CHANGE THE CLEARING DATA FORMAT TO GET SOME MEMORY LEFT AND THAT IS !THAT DISK SHOULD (I HOPE) RUN ON 520-STF,MEGASTE,TT,FALCON AND EVEN CT60. GREETINGS ARE SENT TO PHANTOM, GUNSTICK AND SOTE. YOU ALL ARE COOL OPTIMIZERS !  LEONARD/OXYGENE, 17.03.2005";
const SCROLL_CHAR_WIDTH = 6; 
const SCROLL_CHAR_HEIGHT = 6;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";


// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/leonard/font_pal.dat"));
const back_pal = convertU8ArraytoColors(@embedFile("../assets/screens/leonard/back_pal.dat"));
const ball_pal = convertU8ArraytoColors(@embedFile("../assets/screens/leonard/ball_pal.dat"));

// background
const back_b = @embedFile("../assets/screens/leonard/back.raw");

// bob
const ball_b = @embedFile("../assets/screens/leonard/ball.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------



// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    name: u8 = 0,
    frame_counter: u32 = 0,
    background: Background = undefined,
    scrolltext: Scrolltext = undefined,
    bobs: Bobs = undefined,
    lutSin: [360 * 2]i16 = undefined,
    lutCos: [360 * 2]i16 = undefined,
    lutLen: usize = 360 * 2,
    pxa1: usize = 0,
	pxa2: usize = 0,
	pya1: usize = 0,
	pya2: usize = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        zigos.setBackgroundColor(Color{ .r=28, .g=68, .b=140, .a=255});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(back_pal);
        self.background.init(fb, back_b);

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(ball_pal);
        self.bobs.init(fb, ball_b, 16, 16);
        
        self.lutLen = self.lutSin.len;
        var i: u16 = 0;
        while(i < self.lutLen) : ( i += 1) {
            const a: f32 = (@intToFloat(f32, i) * 2.0 * math.pi) * (1.0 / @intToFloat(f32, self.lutLen));
            self.lutSin[i] = @floatToInt(i16, 32767 * math.sin(a));
            self.lutCos[i] = @floatToInt(i16, 32767 * math.cos(a));
        }        

        // third plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(font_pal);
        self.scrolltext.init(fb, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 194, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {

        var pxb1 = self.pxa1;
        var pxb2 = self.pxa2;
        var pyb1 = self.pya1;
        var pyb2 = self.pya2;
        var i: usize = 0;
        while(i < NB_BOBS) : (  i+= 1) {
            const x_idx: i32 = (160-8) + (( 76 * @intCast(i32, self.lutCos[@mod(pxb1, self.lutLen)]) + 76 * @intCast(i32, self.lutSin[@mod(pxb2, self.lutLen)])) >> 15);
            const y_idx: i32 = (100-8) + (( 44 * @intCast(i32, self.lutCos[@mod(pyb1, self.lutLen)]) + 44 * @intCast(i32, self.lutSin[@mod(pyb2, self.lutLen)])) >> 15);
  
            const x: i16 = @intCast(i16, x_idx);
            const y: i16 = @intCast(i16, y_idx);

            // Console.log("x({}) = {} y({}) = {}", .{ idx, x, idx, y});

            self.bobs.update(i, x, y);

            // Inc loop angles
            pxb1 += 7 * 2;
            pxb2 -= 4 * 2;
            pyb1 += 6 * 2;
            pyb2 -= 3 * 2;            
        }
        // Inc global angles
        self.pxa1 += 3 * 2;
        self.pxa2 += 2 * 2;
        self.pya1 -= 1 * 2;
        self.pya2 += 2 * 2;        

        self.scrolltext.update();   

        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {

        self.background.render();

        self.bobs.fb.clearFrameBuffer(0);
        self.bobs.render();

        self.scrolltext.fb.clearFrameBuffer(0);
        self.scrolltext.render();


        _ = zigos;
    }
};
