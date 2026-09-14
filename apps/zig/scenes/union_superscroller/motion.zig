// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER motion: screen.js update() and the move half of
// scrolltext_horizontal.draw() (codef_scrolltext.js:105-134), in canvas units.
//
//   back/overlay  posVertScrollY1 -= 3.35, back to 0 once <= -399 (screen.js:75-78),
//                 a float64 exactly as in JS: the fraction is what Chrome filters
//   rasters       5 copies 167 apart, -2 a frame, to 167*4 once <= -167 (86-90)
//   letters       init(canvas 640x374, font 384x380, speed 7): wide = 3, so 4
//                 letters from 3*384, 7 px a frame
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");

pub const TEXT = @embedFile("../../assets/screens/union_superscroller/scrolltext.txt"); // main.js:50-229

pub const TILE_W: i32 = 384;
const LETTERS = 4; // wide = ceil(640/384) + 1 = 3; letters 0..wide
const SPEED: i32 = 7;
const BACK_SPEED: f64 = 3.35;
const BACK_WRAP: f64 = -399;
pub const BACK_STEP: f64 = 398;
pub const RASTER_COPIES = 5;
const RASTER_STEP: i32 = 167;
const RASTER_SPEED: i32 = 2;

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| {
        if (c < A.FIRST_CHAR or c >= A.FIRST_CHAR + A.GLYPHS) @compileError("scrolltext character outside fonts2.png");
        if (c == '^') @compileError("scrolltext control codes are not ported: the text has none");
    }
}

pub const Motion = struct {
    y1: f64, // posVertScrollY1
    rasters: [RASTER_COPIES]i32, // posRastersY
    ring: zg.scrollring.Ring(i32, LETTERS),

    /// `offset`: the text's first character, jsApp.mainscrollerPos (screen.js:40, 64).
    pub fn init(self: *Motion, offset: usize) void {
        self.y1 = 0;
        for (&self.rasters, 0..) |*r, i| r.* = RASTER_STEP * @as(i32, @intCast(i));
        self.ring = zg.scrollring.Ring(i32, LETTERS).initAt(TEXT, (LETTERS - 1) * TILE_W, TILE_W, offset);
    }

    /// One melonJS frame's worth: update(), then the letters' move in draw().
    pub fn step(self: *Motion) void {
        self.y1 -= BACK_SPEED;
        if (self.y1 <= BACK_WRAP) self.y1 = 0;
        for (&self.rasters) |*r| {
            r.* -= RASTER_SPEED;
            if (r.* <= -RASTER_STEP) r.* = RASTER_STEP * 4;
        }
        _ = self.ring.stepCount(SPEED);
    }

    /// scrolltext.scroffset: the index of the next character to enter.
    pub fn scroffset(self: *const Motion) usize {
        return self.ring.next;
    }

    /// posVertScrollY1..3: Y2 = Y1 + 398, Y3 = Y2 + 398 (added in that order).
    pub fn backCopies(self: *const Motion) [3]f64 {
        const y2 = self.y1 + BACK_STEP;
        return .{ self.y1, y2, y2 + BACK_STEP };
    }
};
