const std = @import("std");

// --------------------------------------------------------------------------
// Audio engine
//
// Renders interleaved-free stereo f32 at SAMPLE_RATE. The AudioWorklet calls
// `render(frames)` on the audio thread, then reads `left`/`right`.
//
// Foundation stage: emits a test tone. Paula (sample channels) and the YM2149
// chip get mixed in here in later stages; the render() contract stays the same.
// --------------------------------------------------------------------------

pub const SAMPLE_RATE: f32 = 44100.0;
pub const MAX_FRAMES: usize = 4096;

const TAU: f32 = 2.0 * std.math.pi;

pub const Engine = struct {
    left: [MAX_FRAMES]f32 = std.mem.zeroes([MAX_FRAMES]f32),
    right: [MAX_FRAMES]f32 = std.mem.zeroes([MAX_FRAMES]f32),

    // --- foundation: test tone ---
    test_tone_on: bool = true,
    test_tone_hz: f32 = 440.0,
    phase: f32 = 0.0,

    pub fn init(self: *Engine) void {
        self.* = .{};
    }

    pub fn setTestTone(self: *Engine, on: bool, hz: f32) void {
        self.test_tone_on = on;
        self.test_tone_hz = hz;
    }

    pub fn render(self: *Engine, frames: usize) void {
        const n = @min(frames, MAX_FRAMES);

        // clear the working buffers, then let each source add into them
        var i: usize = 0;
        while (i < n) : (i += 1) {
            self.left[i] = 0.0;
            self.right[i] = 0.0;
        }

        if (self.test_tone_on) {
            const inc = TAU * self.test_tone_hz / SAMPLE_RATE;
            i = 0;
            while (i < n) : (i += 1) {
                const s = @sin(self.phase) * 0.2;
                self.left[i] += s;
                self.right[i] += s;
                self.phase += inc;
                if (self.phase >= TAU) self.phase -= TAU;
            }
        }

        // TODO(audio-paula): mix 4 sample channels here
        // TODO(audio-ym): mix YM2149 output here
    }
};
