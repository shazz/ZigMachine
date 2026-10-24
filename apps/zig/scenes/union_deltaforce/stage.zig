// --------------------------------------------------------------------------
// DELTA FORCE's stage: the floor slab, the two logos swapping by squashing flat
// (screen.js:143-157, 341) and the three balls that jump when a YM voice's
// volume changes (the "bad volume equalizer", screen.js:163-176, 343-345).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const stretch = @import("../union_common/stretch.zig");

/// logoHeight / logoSize / logoTile / logoCounter.
pub const Logo = struct {
    height: f64,
    size: f64,
    tile: u1,
    counter: u32,

    const SIZE: f64 = 0.035;
    const HOLD = 45 * 3; // frames at full height, less one
    const CENTRE_Q16: i32 = 65 * 32768; // 65/2 in Q16: drawTile(..., 320, 65, 1, 0, 1, logoHeight), mid-handled

    pub fn init(self: *Logo) void {
        self.height = 1;
        self.size = SIZE;
        self.tile = 0;
        self.counter = 0;
    }

    pub fn update(self: *Logo) void {
        self.height -= self.size;
        if (self.height <= 0) {
            self.size = -SIZE;
            self.tile = 1 - self.tile;
        } else if (self.height >= 1) {
            self.size = 0;
            if (self.counter == HOLD) { // logoCounter++ == 45*3
                self.size = SIZE;
                self.counter = 0;
            } else self.counter += 1;
        }
    }
};

/// ymCurrentVoices / ymLastVoices: a voice whose volume register changed shows
/// ball frame 15-7, then shrinks a frame at a time back to frame 15.
pub const Voices = struct {
    last: [3]u8,
    level: [3]u8,

    const FLASH = 7;

    pub fn init(self: *Voices) void {
        self.last = @splat(0);
        self.level = @splat(0);
    }

    /// `regs` are the live YM registers; ym.js keeps voice.vol = reg & 31.
    pub fn update(self: *Voices, regs: *const [16]u8) void {
        for (&self.last, &self.level, regs[8..11]) |*last, *level, reg| {
            const vol = reg & 31;
            if (vol != last.*) level.* = FLASH else if (level.* > 0) level.* -= 1;
            last.* = vol;
        }
    }
};

const FLOOR_X = 6 / 2; // slab.draw(main, 6, 192)
const FLOOR_Y = 192 / 2;
const BALLS_X = 160 / 2; // balls at x 160, 256, 352: one ball width apart
const BALLS_Y = 140 / 2;
const LAST_FRAME = 15;
/// The logo lives in rows 0..64, the floor and balls in 70..126 and the two bands
/// in BOTTOM_Y.. (assets.zig): three windows that do not overlap, so each is
/// cleared and redrawn only when what it shows has changed (the ST's "only
/// modify what changes": the logo holds 135 frames, the balls follow the music,
/// a ball at a time).
const SPLIT = 68;

/// What each window was last painted from; null until painted.
pub const Painted = struct {
    logo: ?struct { height: f64, tile: u1 } = null,
    levels: ?[3]u8 = null,
};

pub fn draw(dst: blit.Dst, img: *const A.Images, logo: *const Logo, voices: *const Voices, painted: *Painted) void {
    const top = dst.window(0, 0, dst.w, SPLIT);
    if (painted.logo == null or painted.logo.?.height != logo.height or painted.logo.?.tile != logo.tile) {
        top.fill(0, 0, top.w, top.h, A.BLACK); // maincanvas.fill('#000000')
        stretch.stretchY(top, img.logo(logo.tile), 0, Logo.CENTRE_Q16, logo.height, null, .copy);
        painted.logo = .{ .height = logo.height, .tile = logo.tile };
    }
    const mid = dst.window(0, SPLIT, dst.w, A.BOTTOM_Y - SPLIT);
    if (painted.levels) |was| {
        // Only the run of balls whose frame changed is redrawn (the music changes a voice
        // most frames, rarely all three, and the floor never moves).
        var k0: usize = 3;
        var k1: usize = 0;
        for (was, voices.level, 0..) |a, b, k| if (a != b) {
            k0 = @min(k0, k);
            k1 = k + 1;
        };
        if (k1 > k0) redrawBalls(mid, img, voices, k0, k1);
    } else {
        mid.fill(0, 0, mid.w, mid.h, A.BLACK);
        blit.blit(mid, img.floor, null, FLOOR_X, FLOOR_Y - SPLIT, 0, .copy);
        drawBalls(mid, img, voices, 0, 3);
    }
    painted.levels = voices.level;
}

comptime { // the balls' box lies inside the floor's columns and holds all the floor's rows
    std.debug.assert(BALLS_X >= FLOOR_X and BALLS_X + 3 * A.BALL_W <= FLOOR_X + A.FLOOR_W);
    std.debug.assert(BALLS_Y <= FLOOR_Y and FLOOR_Y + A.FLOOR_H <= BALLS_Y + A.BALL_H);
}

/// The window's paint over balls k0..k1-1's box, which only the black field, the floor
/// and those balls (side by side, never overlapping) cover: the same pixels as a full repaint.
fn redrawBalls(mid: blit.Dst, img: *const A.Images, voices: *const Voices, k0: usize, k1: usize) void {
    const x0 = BALLS_X + k0 * A.BALL_W;
    const w = (k1 - k0) * A.BALL_W;
    mid.fill(@intCast(x0), BALLS_Y - SPLIT, w, A.BALL_H, A.BLACK);
    const under = blit.Rect{ .x = x0 - FLOOR_X, .y = 0, .w = w, .h = A.FLOOR_H };
    blit.blit(mid, img.floor, under, @intCast(x0), FLOOR_Y - SPLIT, 0, .copy);
    drawBalls(mid, img, voices, k0, k1);
}

fn drawBalls(mid: blit.Dst, img: *const A.Images, voices: *const Voices, k0: usize, k1: usize) void {
    for (voices.level[k0..k1], k0..) |level, k| {
        const frame: usize = LAST_FRAME - level;
        const part = blit.Rect{ .x = frame * A.BALL_W, .y = 0, .w = A.BALL_W, .h = A.BALL_H };
        blit.blit(mid, img.balls, part, @intCast(BALLS_X + k * A.BALL_W), BALLS_Y - SPLIT, 0, .copy);
    }
}
