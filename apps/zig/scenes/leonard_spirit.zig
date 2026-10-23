// --------------------------------------------------------------------------
// LEONARD'S SPIRIT: the `leonard` cart (Leonard/Oxygene's 312-sprite record,
// Atari ST hardcore optimisation contest, 17.03.2005, http://leonard.oxg.free.fr/
// ; after Dyno's CODEF remake) redone the way Leonard did the record itself:
// precompute everything, draw only what must be drawn, and see how many 16x16
// balls ZIGGY can move in one frame. Same ball, background, 6x6 scroller, the
// same Lissajous family and Mad Max's S.O.S.; the leonard cart stays as it is.
//
// Leonard's method, as he told it on atari-forum (March 2005): a PC
// "databuilder" does all the thinking, a dumb ST player only runs its output:
//   - every ball is GENERATED CODE, a MOVE sprite: one routine per pixel
//     shift, immediate values stored at immediate offsets, no mask, no loop
//     (leonard_spirit/ball.zig: 4 shifts on the chunky plane, 72 aligned
//     stores a ball, built at compile time from ball.raw);
//   - the path is a table walk: sine table, start angles per frame, all
//     built at compile time (leonard_spirit/path.zig); the scrolltext is one
//     strip rendered at compile time (leonard_spirit/scroll.zig);
//   - the clear: one CHISEL copy of the background from cart RAM (~64K
//     clocks), cheaper here than any clear list once the balls cover most of
//     the screen. His "don't clear what you redraw" and partial (OR) sprites
//     are per-frame DATA, and measured on this path they don't fit: the
//     frame-to-frame pixel diff is 4.5-9 K pixels (~2-3 MB for the 360-frame
//     period, more than the 2 MB cart window, and a film, not sprites); the
//     visible row range of each ball (1 byte a ball a frame) halves the
//     stores but costs NB x 360 bytes (~900 KB) and skips the hidden balls.
//
// ONE plane (every enabled plane costs ~0.59 Mc of FRESCO a frame): the old
// cart's three (picture, balls, scroller) become painter's order in plane 0,
// palettes merged: 0-3 picture, 4-6 ball, 7 scroller ink.
// Board budget (apps/frame_cost.mjs, cost model of 2026-10-23): see NB below.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ball_mod = @import("leonard_spirit/ball.zig");
const path = @import("leonard_spirit/path.zig");
const scroll = @import("leonard_spirit/scroll.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const WIDTH: u32 = zg.WIDTH;

// The record: eight times Leonard's 312, every ball drawn in full every frame.
// frame_cost (2026-10-23 model): 1.51 Mc/frame = cart 0.68 + CHISEL 0.13 +
// FRESCO 0.70 (one plane), under the 60 fps knee (1.75-2.1 Mc).
pub const NB: u32 = path.SNAKES * path.SNAKE_LEN;

// Mad Max, "S.O.S." from the So Watt demo (1989), as the leonard cart.
const MUSIC = "sos.sndh";

const A = "../assets/screens/leonard/";
const back_b = @embedFile(A ++ "back.raw");
const ball_b = @embedFile(A ++ "ball.raw");
const font_b = @embedFile(A ++ "font.raw");

// merged palette: picture 0-3, ball 1-3 -> 4-6, font ink 1 -> 7
pub const BALL_INK = 3;
pub const FONT_INK = 7;
const palette: [256]Color = blk: {
    const back = zg.convertU8ArraytoColors(@embedFile(A ++ "back_pal.dat"));
    const ball = zg.convertU8ArraytoColors(@embedFile(A ++ "ball_pal.dat"));
    const font = zg.convertU8ArraytoColors(@embedFile(A ++ "font_pal.dat"));
    var p = [_]Color{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 256;
    for (0..4) |i| p[i] = back[i];
    for (1..4) |i| p[BALL_INK + i] = ball[i];
    p[FONT_INK] = font[1];
    break :blk p;
};

pub const Ball = ball_mod.Sprite(16, 16, ball_b.*, BALL_INK, WIDTH);
pub const Chain = path.Chain;

const TEXT_2005 = "HI EVERYBODY ! ULTRA OPTIMISATION RULES, EVEN FOR STUPID RECORD ! I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO !  I TOTALLY REWRITE MY PC DATABUILDER TO IMPLEMENT NEW STUFF. THEN, I CHANGE THE CLEARING DATA FORMAT TO GET SOME MEMORY LEFT AND THAT IS !THAT DISK SHOULD (I HOPE) RUN ON 520-STF,MEGASTE,TT,FALCON AND EVEN CT60. GREETINGS ARE SENT TO PHANTOM, GUNSTICK AND SOTE. YOU ALL ARE COOL OPTIMIZERS !  LEONARD/OXYGENE, 17.03.2005";
const TEXT_NOW = std.fmt.comptimePrint("      ...AND THE STUPID RECORD STRIKES BACK ! {d} SPRITES = 8 TIMES 312, ALL OF THEM DRAWN EVERY FRAME, 60 FPS ON ZIGGY. SAME SPIRIT AS 2005 : THE DATABUILDER DOES THE THINKING, THE PLAYER JUST RUNS. EACH BALL IS GENERATED CODE, 72 MOVES AND NOT ONE MASK, ONE BLITTER COPY FOR THE CLEAR, ONE PLANE, NOTHING COMPUTED TWICE. WHO WANTS TO BEAT IT ?  ULTRA OPTIMISATION STILL RULES !", .{NB});
pub const TEXT = " " ** 92 ++ TEXT_2005 ++ TEXT_NOW;
pub const Strip = scroll.Strip(font_b, TEXT, FONT_INK);
const SCROLL_Y = 194;
const SCROLL_TICKS: u32 = Strip.TEXT_W / scroll.SPEED; // one lap of the text

// State the harness reads (leonard_spirit/testapi.zig).
pub var frame: u32 = 0; // 0..359, the path's phase
pub var tick: u32 = 0; // the scroller's
pub var plane: [*]align(4) u8 = undefined;

pub const Demo = struct {
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        zg.requestSong(MUSIC);
        zigos.setBackgroundColor(Color{ .r = 28, .g = 68, .b = 140, .a = 255 });
        self.blitter.init();
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(palette);
        plane = @alignCast(fb.fb); // the generated stores need a u32-aligned plane
        frame = 0;
        tick = 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = self;
        _ = zigos;
        _ = elapsed_time;
    }

    // Painter's order: picture, balls (first to last), scroller on top. Then
    // the counters step, so the first frame shown is frame 0.
    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        const fb = &zigos.lfbs[0];
        self.blitter.blitImage(fb, 0, 0, back_b, WIDTH, 0, 0, WIDTH, 200, null);
        drawBalls(frame);
        self.blitter.blitImage(fb, 0, SCROLL_Y, &Strip.pixels, Strip.W, Strip.windowX(tick), 0, WIDTH, scroll.CW, 0);
        frame = if (frame + 1 == path.PERIOD) 0 else frame + 1;
        tick = if (tick + 1 == SCROLL_TICKS) 0 else tick + 1;
    }
};

fn drawBalls(f: u32) void {
    var k: u32 = 0;
    while (k < path.SNAKES) : (k += 1) {
        var c = Chain.start(f, k);
        var i: u32 = 0;
        while (i < path.SNAKE_LEN) : (i += 1) {
            Ball.draw(plane, c.x(), c.y());
            c.next();
        }
    }
}

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("leonard_spirit/testapi.zig");
    }
}
