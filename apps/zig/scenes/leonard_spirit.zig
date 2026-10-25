// --------------------------------------------------------------------------
// LEONARD'S SPIRIT: the `leonard` cart (Leonard/Oxygene's 312-sprite record,
// Atari ST hardcore optimisation contest, 17.03.2005, http://leonard.oxg.free.fr/
// ; after Dyno's CODEF remake) redone the way Leonard did the record itself:
// precompute everything, draw only what must be drawn, and see how many 16x16
// balls ZIGGY can move in one frame, then go FULLSCREEN: the borders shake
// open one side at a time and the background starts to pan on the hardware
// scroll (leonard_spirit/show.zig). Same ball, background, 6x6 scroller,
// the same Lissajous family and Mad Max's S.O.S.; the leonard cart stays.
//
// Leonard's method, as he told it on atari-forum (March 2005): a PC
// "databuilder" does all the thinking, a dumb ST player only runs its output:
//   - every ball is GENERATED CODE, a MOVE sprite: one routine per pixel
//     shift, immediate values stored at immediate offsets, no mask, no loop
//     (leonard_spirit/ball.zig: 72 aligned stores a ball, compile time);
//   - the path, the scroll, the show and the scrolltext strip are
//     compile-time tables (path.zig, show.zig, scroll.zig);
//   - the clear is the window, restored by CHISEL from the tile in cart RAM
//     at the scrolled coordinates (restore.zig says why not a clear list).
//
// ONE plane, an overscan SCROLL plane (layout.zig): the hardware pans the
// 400x280 window over a 576x448 buffer, the balls are drawn at window
// position + scroll so they stay put. A second plane for the background
// would cost one more FRESCO pass a frame for the same clear. Palettes
// merged: 0-3 picture, 4-6 ball, 7 scroller ink. Borders open for real: the
// plane's HBL flickers the resolution at the magic column on the lines of
// each open side (borderHbl), never on a closed one.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ball_mod = @import("leonard_spirit/ball.zig");
const path = @import("leonard_spirit/path.zig");
const scroll = @import("leonard_spirit/scroll.zig");
const show = @import("leonard_spirit/show.zig");
const restore = @import("leonard_spirit/restore.zig");
const lay = @import("leonard_spirit/layout.zig");
const text = @import("leonard_spirit/text.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

// The record: SNAKES times Leonard's 312, every ball drawn in full every frame.
// frame_cost (2026-10-23 model), the same in every phase of the show:
// 1.55 Mc = cart 0.61 + CHISEL 0.23 (the window, 9 blits) + FRESCO 0.70;
// --budget: cart 0.85 of 1.13 Mc. 8 snakes would be ~1.63 Mc (over the
// 1.6 aim). Two planes (background on its own scrolled plane) measured
// 2.16 Mc with these 7 snakes: ~46 fps.
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

pub const Ball = ball_mod.Sprite(16, 16, ball_b.*, BALL_INK, lay.BUF_W);
pub const Strip = scroll.Strip(font_b, text.full(NB, path.SNAKES), FONT_INK);
const SCROLL_TICKS: u32 = Strip.TEXT_W / scroll.SPEED; // one lap of the text

// The tile origin: tile (0,0) at the window's (BX, BY) on the first frame.
pub const OX = path.SCROLL[0].x + lay.BX;
pub const OY = path.SCROLL[0].y + lay.BY;

// State the harness reads (leonard_spirit/testapi.zig).
pub var t: u32 = 0; // frames since the start, held at show.CRUISE
pub var frame: u32 = 0; // the balls' phase, 0..359
pub var phase: u32 = 0; // the scroll's phase, Q16 path frames, 0..360<<16
pub var tick: u32 = 0; // the scroller's
pub var open_mask: u8 = 0; // the borders the HBL opens this frame
pub var plane: [*]align(4) u8 = undefined;

// Per line of the window: flicker on the lines of an open side only, at the
// magic column. Top and bottom open causally from their first line.
fn borderHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const want = if (line == 0) open_mask & 4 != 0 else if (line < lay.BY) false else if (line < lay.BY + 200) open_mask & 1 != 0 else if (line == lay.BY + 200) open_mask & 2 != 0 else false;
    if (want) fb.flickerBorder();
}

pub const Demo = struct {
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        zg.requestSong(MUSIC);
        self.blitter.init();
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanScrollPlane(lay.BUF_W, lay.BUF_H);
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, borderHbl);
        fb.setPalette(palette);
        zigos.setBackgroundColor(Color{ .r = 28, .g = 68, .b = 140, .a = 255 }); // the closed borders
        plane = @alignCast(fb.fb); // the generated stores need a u32-aligned plane
        t = 0;
        frame = 0;
        phase = 0;
        tick = 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = self;
        _ = zigos;
        _ = elapsed_time;
    }

    // Pan, then painter's order: the window's background, the balls (first to
    // last), the scroller. Then the counters step: the first frame is t = 0.
    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        const fb = &zigos.lfbs[0];
        const s = path.SCROLL[phase >> 16];
        open_mask = show.openMask(t);
        fb.setScroll(s.x, s.y);
        restore.window(&self.blitter, fb, back_b, s.x, s.y, OX, OY);
        drawBalls(frame, s);
        var band = restore.rowView(fb, s.y + lay.SCROLL_Y);
        self.blitter.blitImage(&band, @intCast(s.x), 0, &Strip.pixels, Strip.W, Strip.windowX(tick), 0, lay.WIN_W, scroll.CW, 0);
        phase = show.stepPhase(phase, t);
        frame = if (frame + 1 == path.PERIOD) 0 else frame + 1;
        tick = if (tick + 1 == SCROLL_TICKS) 0 else tick + 1;
        if (t < show.CRUISE) t += 1;
    }
};

fn drawBalls(f: u32, s: path.Pan) void {
    var k: u32 = 0;
    while (k < path.SNAKES) : (k += 1) {
        var c = path.Chain.start(f, k);
        var i: u32 = 0;
        while (i < path.SNAKE_LEN) : (i += 1) {
            Ball.draw(plane, c.x() + s.x, c.y() + s.y);
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
