// --------------------------------------------------------------------------
// DELTA FORCE's stage: the floor slab, the two logos swapping by squashing flat
// (screen.js:143-157, 341) and the three balls that jump when a YM voice's
// volume changes (the "bad volume equalizer", screen.js:163-176, 343-345).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

/// logoHeight / logoSize / logoTile / logoCounter.
pub const Logo = struct {
    height: f64,
    size: f64,
    tile: u1,
    counter: u32,

    const SIZE: f64 = 0.035;
    const HOLD = 45 * 3; // frames at full height, less one
    const CENTRE_Y: f64 = 65.0 / 2.0; // drawTile(..., 320, 65, 1, 0, 1, logoHeight), mid-handled

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

pub fn draw(dst: blit.Dst, img: *const A.Images, logo: *const Logo, voices: *const Voices) void {
    blit.blit(dst, img.floor, null, FLOOR_X, FLOOR_Y, 0, .copy);
    blit.stretchY(dst, img.logo(logo.tile), 0, Logo.CENTRE_Y, logo.height, null, .copy);
    for (voices.level, 0..) |level, k| {
        const frame: usize = LAST_FRAME - level;
        const part = blit.Rect{ .x = frame * A.BALL_W, .y = 0, .w = A.BALL_W, .h = A.BALL_H };
        blit.blit(dst, img.balls, part, @intCast(BALLS_X + k * A.BALL_W), BALLS_Y, 0, .copy);
    }
}
