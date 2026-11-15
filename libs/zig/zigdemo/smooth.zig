//! zigdemo smooth: the picture's clock, SMOOTHED against the music. The music is the master, but a
//! decoder's position (zigdemo.mp3: what BARD has decoded) moves in whole frames (1,152 samples =
//! 26.1 ms at 44.1 kHz) and in bursts when the decoder shares its CPU: a 60 Hz picture read straight
//! from it steps unevenly (25 Hz pictures stutter, a picture stands still while the music plays on
//! from its buffer).
//! So the picture's time runs on the VBL (16.667 ms a frame, exact over three frames) and is pulled
//! toward the music only gently: past a dead band, by 1/`pull` of the error and at most `step_us` a
//! frame; an error past `snap_us` (the music re-seeked) is taken at once. A seek or a pause of the
//! demo's clock re-anchors it (reset()). The VBL and the audio rate come from one board clock, so the
//! pull only ever corrects the decoder's lag, never a drift.
//! The defaults are the ones measured on the board with an MP3 on BARD (15 Nov 2026).

pub const Config = struct {
    dead_us: i64 = 40_000, // no pull inside this error
    pull: i64 = 16, // the pull is error / pull ...
    step_us: i64 = 2_000, // ... and at most this a frame (12 %: inaudible, invisible)
    snap_us: i64 = 1_500_000, // past this error the music re-seeked: jump
};

const FRAME3_US: i64 = 50_000; // three 60 Hz frames

pub fn Smooth(comptime cfg: Config) type {
    return struct {
        const Self = @This();
        t_us: i64 = 0, // the picture's time
        phase: u2 = 0, // which of three frames (16,666 / 16,667 / 16,667 us)
        valid: bool = false,

        pub fn reset(self: *Self) void {
            self.valid = false;
        }

        /// The picture's time in ms this frame, from the music's position `m_us` (its samples in us).
        pub fn at(self: *Self, m_us: i64) u32 {
            if (!self.valid) {
                self.t_us = m_us;
                self.phase = 0;
                self.valid = true;
            } else self.step(m_us);
            return @intCast(@divFloor(@max(self.t_us, 0), 1000));
        }

        fn step(self: *Self, m: i64) void {
            self.phase = if (self.phase == 2) 0 else self.phase + 1;
            self.t_us += if (self.phase == 0) FRAME3_US - 2 * 16_667 else 16_667;
            const e = m - self.t_us;
            if (e > cfg.snap_us or e < -cfg.snap_us) {
                self.t_us = m;
            } else if (e > cfg.dead_us) {
                self.t_us += @min(@divTrunc(e, cfg.pull), cfg.step_us);
            } else if (e < -cfg.dead_us) {
                self.t_us -= @min(@divTrunc(-e, cfg.pull), cfg.step_us);
            }
        }
    };
}
