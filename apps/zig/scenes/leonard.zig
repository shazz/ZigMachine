// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const math = std.math;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const Bobs = zg.Bobs;
const Background = zg.Background;
const Scrolltext = zg.Scrolltext;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max, "S.O.S." from the So Watt demo (1989). The ripped image tags
// itself TITL "So Watt - TCB"; the archive files it under the screen name.
const MUSIC = "sos.sndh";

pub const PHYSICAL_WIDTH: u16 = zg.PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = zg.PHYSICAL_HEIGHT;

pub const NB_FONTS: u8 = 320 / 6 + 1;
const fonts_b = @embedFile("../assets/screens/leonard/font.raw");
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
const NB_BOBS = 312;
// Table length as a constant so `%` below is a multiply-shift, not a soft divide.
const LUT_LEN: usize = 360 * 2;
const bobs_images: [NB_BOBS][]const u8 = [_][]const u8{ball_b} ** NB_BOBS;

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
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    bobs: Bobs(NB_BOBS) = undefined,
    lutSin: [360 * 2]i16 = undefined,
    lutCos: [360 * 2]i16 = undefined,
    lutLen: usize = 360 * 2,
    blitter: zg.Blitter = .{},
    pxa1: usize = 0,
    pxa2: usize = 0,
    pya1: usize = 0,
    pya2: usize = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        zigos.setBackgroundColor(Color{ .r = 28, .g = 68, .b = 140, .a = 255 });

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(back_pal);
        self.background.init(fb.getRenderTarget(), back_b, 0);
        // The picture never changes and planes persist: draw it once, not every frame.
        self.background.render();
        self.blitter.init();

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(ball_pal);
        self.bobs = Bobs(NB_BOBS).init(fb.getRenderTarget(), bobs_images, 16, 16);
        self.blitter.clear(fb, 0);

        self.lutLen = self.lutSin.len;
        var i: u16 = 0;
        while (i < self.lutLen) : (i += 1) {
            const a: f32 = (@as(f32, @floatFromInt(i)) * 2.0 * math.pi) * (1.0 / @as(f32, @floatFromInt(self.lutLen)));
            self.lutSin[i] = @as(i16, @intFromFloat(32767 * math.sin(a)));
            self.lutCos[i] = @as(i16, @intFromFloat(32767 * math.cos(a)));
        }

        // third plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(font_pal);
        self.blitter.clear(fb, 0);
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 194, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        var pxb1 = self.pxa1;
        var pxb2 = self.pxa2;
        var pyb1 = self.pya1;
        var pyb2 = self.pya2;
        var i: usize = 0;
        while (i < NB_BOBS) : (i += 1) {
            const x_idx: i32 = (160 - 8) + ((76 * @as(i32, @intCast(self.lutCos[pxb1 % LUT_LEN])) + 76 * @as(i32, @intCast(self.lutSin[pxb2 % LUT_LEN]))) >> 15);
            const y_idx: i32 = (100 - 8) + ((44 * @as(i32, @intCast(self.lutCos[pyb1 % LUT_LEN])) + 44 * @as(i32, @intCast(self.lutSin[pyb2 % LUT_LEN]))) >> 15);

            const x: i16 = @as(i16, @intCast(x_idx));
            const y: i16 = @as(i16, @intCast(y_idx));

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
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        // 312 keyed 16x16 blits (colour 0 is transparent: ball_pal[0] has alpha 0,
        // which is what Sprite.render keyed on) instead of 80k CPU pixel stores.
        const bobs_fb = &zigos.lfbs[1];
        self.blitter.clear(bobs_fb, 0);
        for (0..NB_BOBS) |i| {
            self.blitter.blitImage(bobs_fb, self.bobs.positions_x[i], self.bobs.positions_y[i], ball_b, 16, 0, 0, 16, 16, 0);
        }

        // The scroller only ever draws on the last six rows: clear just those.
        self.blitter.fill(&zigos.lfbs[2], 0, 194, WIDTH, SCROLL_CHAR_HEIGHT, 0);
        self.scrolltext.render();

        _ = elapsed_time;
    }
};
