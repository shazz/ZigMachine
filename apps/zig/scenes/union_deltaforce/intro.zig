// --------------------------------------------------------------------------
// DELTA FORCE's credits band (screen.js:89-107, 179-220, 415-433): two 10-letter
// words side by side on a 1280-wide canvas, sine-waved, sliding by 14 canvas
// pixels a frame between showing the left word (x 0) and the right one
// (x -640), stopping for the word's frame count at each end.
//
// The state machine is screen.js's, quirks kept: the overshooting frame of a
// turn is not clamped, so a stop after a turn counts from 1. FX_RESET (the
// scrolltext's 'g') restarts it; screen.js forgets the speed there, the port
// resets it too so every run is the first one (a deliberate deviation, see Demo).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const Band = @import("band.zig").Band;

const Word = struct { left: *const [10]u8, right: *const [10]u8, hold: u32 };

/// introEffects (screen.js:89-103).
const WORDS = [_]Word{
    .{ .left = "MEGA DEMO!", .right = "          ", .hold = 42 },
    .{ .left = "MEGA DEMO!", .right = "CODING BY:", .hold = 42 },
    .{ .left = "-NEW MODE-", .right = "CODING BY:", .hold = 42 },
    .{ .left = "-NEW MODE-", .right = "GRAPHIX BY", .hold = 42 },
    .{ .left = "  -SLIME- ", .right = "GRAPHIX BY", .hold = 42 },
    .{ .left = "  -SLIME- ", .right = "   AND    ", .hold = 42 },
    .{ .left = "QUESTLORD!", .right = "   AND    ", .hold = 42 },
    .{ .left = "QUESTLORD!", .right = "MUZAK BY: ", .hold = 42 },
    .{ .left = " MAD MAX  ", .right = "MUZAK BY: ", .hold = 42 },
    .{ .left = " MAD MAX  ", .right = "          ", .hold = 42 },
    .{ .left = "  HELLO   ", .right = "          ", .hold = 4 },
    .{ .left = "  HELLO   ", .right = "          ", .hold = 4 },
};

/// C_STATES: introTime 0, 1 and 2.
pub const Part = enum(u8) { intro_only, intro_and_outro, outro };

const SPEED = 14; // introScrollSpeed
const LEFT_END = -640;
const GLYPH_C = 64;
// scrollfxparam_intro: {value: 10, amp: 30, inc: 0.004, offset: -0.09}, siny(0, 110/2 - 16)
const WAVE_START: f64 = 10;
const WAVE_AMP: f64 = 30;
const WAVE_INC: f64 = 0.004;
const WAVE_OFFSET: f64 = -0.09;
const WAVE_Y: f64 = 110 / 2 - 16;
const CENTRE_Y: f64 = (280.0 + 110.0 / 2.0) / 2.0;

pub const Intro = struct {
    part: Part,
    word: usize, // currentIntroEffect
    pos: i32, // intropartPos, canvas pixels
    speed: i32,
    stopped: u32, // introStopTime
    wave: f64, // scrollfx_intro's value
    drawn_wave: f64, // the value this frame's siny starts from
    visible: bool, // drawn this frame

    pub fn init(self: *Intro) void {
        self.part = .intro_only;
        self.speed = SPEED;
        self.wave = WAVE_START;
        self.drawn_wave = WAVE_START;
        self.visible = false;
        self.restart();
    }

    /// FX_RESET's part (screen.js:394-398), plus the speed (the deviation); the
    /// wave carries on.
    pub fn restart(self: *Intro) void {
        self.speed = SPEED;
        self.part = .intro_only;
        self.word = 0;
        self.pos = -640;
        self.stopped = 0;
    }

    /// update(), screen.js:179-220.
    pub fn update(self: *Intro) void {
        if (self.part != .outro) {
            self.pos += self.speed;
            if (self.pos >= 0) {
                if (self.stop()) {
                    if (self.word >= WORDS.len - 1) self.part = .intro_and_outro; // last word
                } else self.pos = 0;
            } else if (self.pos <= LEFT_END) {
                if (!self.stop()) self.pos = LEFT_END;
            }
        }
        if (self.part == .intro_and_outro and self.pos <= LEFT_END) self.part = .outro;
    }

    /// One frame at an end; true when the stop is over and the band turns.
    fn stop(self: *Intro) bool {
        self.stopped += 1;
        if (self.stopped != hold(self.word)) return false;
        self.speed = -self.speed;
        self.word += 1;
        self.stopped = 0;
        return true;
    }

    /// draw()'s own state change: siny leaves the wave at its start + offset.
    pub fn advance(self: *Intro) void {
        self.visible = self.part != .outro;
        if (!self.visible) return;
        self.drawn_wave = self.wave;
        self.wave = self.drawn_wave + WAVE_OFFSET;
    }

    pub fn draw(self: *const Intro, dst: blit.Dst, band: *Band, img: *const A.Images, gold_y: u32, twist: f64) void {
        if (!self.visible) return;
        const w = WORDS[@min(self.word, WORDS.len - 1)];
        band.clear();
        for (w.left, w.right, 0..) |l, r, i| {
            const x: i32 = @intCast(i * GLYPH_C);
            band.letter(&img.font, l, x);
            band.letter(&img.font, r, 640 + x);
        }
        const sum = zg.wave.SineSum(f64, 1){ .base = WAVE_Y, .amp = .{WAVE_AMP}, .phase = .{self.drawn_wave}, .inc = .{WAVE_INC}, .rounding = .round };
        var sweep = sum.sweep(0);
        band.compose(&sweep, img.gold, gold_y);
        band.draw(dst, @divFloor(self.pos, 2), CENTRE_Y, @cos(twist));
    }
};

/// introEffects[i][2]. Past the table the original throws (a TypeError) and
/// freezes; no sequence of the screen's own gets there, and the port just holds.
fn hold(word: usize) u32 {
    return if (word < WORDS.len) WORDS[word].hold else std.math.maxInt(u32);
}
