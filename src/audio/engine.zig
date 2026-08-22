const std = @import("std");

// --------------------------------------------------------------------------
// Audio engine
//
// Renders stereo f32 at SAMPLE_RATE. The AudioWorklet calls render(frames) on
// the audio thread, then reads `left`/`right`.
//
// Sources mixed here:
//   - Paula: NUM_CHANNELS digital sample channels (8-bit signed PCM, the
//     Amiga/MOD native format), each with rate/volume/pan and optional loop.
//   - test tone (foundation) — kept for diagnostics.
//   - TODO(audio-ym): YM2149 chip output.
//
// A ProTracker .MOD sequencer (later) just drives the Paula channels via
// noteOn()/setRate()/setVolume(); it does not touch the mixing math.
// --------------------------------------------------------------------------

pub const SAMPLE_RATE: f32 = 44100.0;
pub const MAX_FRAMES: usize = 4096;
pub const NUM_CHANNELS: usize = 4;

const TAU: f32 = 2.0 * std.math.pi;

// Fixed-point position: 16 fractional bits, integer part in the high bits.
const FRAC_BITS: u6 = 16;
const FRAC_ONE: u32 = 1 << FRAC_BITS;

// One Paula-style sample channel.
pub const Channel = struct {
    data: []const i8 = &.{}, // 8-bit signed PCM
    pos: u64 = 0, // fixed-point index into data (FRAC_BITS fractional)
    step: u32 = 0, // fixed-point samples advanced per output frame
    loop_start: u32 = 0, // in samples
    loop_len: u32 = 0, // in samples; <= 1 means "no loop"
    volume: f32 = 1.0, // 0..1
    pan: f32 = 0.0, // -1 = full left, +1 = full right
    active: bool = false,

    fn mixInto(self: *Channel, left: []f32, right: []f32, n: usize) void {
        if (!self.active or self.data.len == 0) return;

        const looping = self.loop_len > 1;
        const loop_end: u64 = (@as(u64, self.loop_start) + self.loop_len) << FRAC_BITS;
        const loop_span: u64 = @as(u64, self.loop_len) << FRAC_BITS;
        const data_end: u64 = @as(u64, self.data.len) << FRAC_BITS;

        // linear pan: pan -1 -> (1,0), 0 -> (1,1), +1 -> (0,1)
        const lgain = self.volume * @min(@as(f32, 1.0), 1.0 - self.pan);
        const rgain = self.volume * @min(@as(f32, 1.0), 1.0 + self.pan);

        var p = self.pos;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (looping) {
                while (p >= loop_end) p -= loop_span;
            } else if (p >= data_end) {
                self.active = false;
                break;
            }
            const idx: usize = @intCast(p >> FRAC_BITS);
            const s = @as(f32, @floatFromInt(self.data[idx])) * (1.0 / 128.0);
            left[i] += s * lgain;
            right[i] += s * rgain;
            p += self.step;
        }
        self.pos = p;
    }
};

pub const Engine = struct {
    left: [MAX_FRAMES]f32 = std.mem.zeroes([MAX_FRAMES]f32),
    right: [MAX_FRAMES]f32 = std.mem.zeroes([MAX_FRAMES]f32),

    channels: [NUM_CHANNELS]Channel = [_]Channel{.{}} ** NUM_CHANNELS,

    // diagnostics
    test_tone_on: bool = false,
    test_tone_hz: f32 = 440.0,
    phase: f32 = 0.0,

    // a synthetic one-cycle sine sample, so the Paula path can be proven with
    // no external data. 64 signed-8-bit samples.
    test_sample: [64]i8 = undefined,

    pub fn init(self: *Engine) void {
        self.* = .{};
        var i: usize = 0;
        while (i < self.test_sample.len) : (i += 1) {
            const ph = TAU * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.test_sample.len));
            self.test_sample[i] = @intFromFloat(@sin(ph) * 110.0);
        }
    }

    pub fn setTestTone(self: *Engine, on: bool, hz: f32) void {
        self.test_tone_on = on;
        self.test_tone_hz = hz;
    }

    // Play the built-in synthetic sample on a channel, looped, at `hz` cycles/sec.
    pub fn testSampleOn(self: *Engine, ch: usize, on: bool, hz: f32) void {
        if (ch >= NUM_CHANNELS) return;
        var c = &self.channels[ch];
        if (!on) {
            c.active = false;
            return;
        }
        c.data = &self.test_sample;
        c.pos = 0;
        c.loop_start = 0;
        c.loop_len = @intCast(self.test_sample.len);
        c.volume = 0.3;
        c.pan = 0.0;
        // playback rate so the 64-sample cycle repeats `hz` times/sec
        const rate = hz * @as(f32, @floatFromInt(self.test_sample.len));
        c.step = @intFromFloat(rate / SAMPLE_RATE * @as(f32, FRAC_ONE));
        c.active = true;
    }

    pub fn render(self: *Engine, frames: usize) void {
        const n = @min(frames, MAX_FRAMES);
        const l = self.left[0..n];
        const r = self.right[0..n];

        var i: usize = 0;
        while (i < n) : (i += 1) {
            l[i] = 0.0;
            r[i] = 0.0;
        }

        // Paula sample channels
        for (&self.channels) |*c| {
            c.mixInto(l, r, n);
        }

        // diagnostic test tone
        if (self.test_tone_on) {
            const inc = TAU * self.test_tone_hz / SAMPLE_RATE;
            i = 0;
            while (i < n) : (i += 1) {
                const s = @sin(self.phase) * 0.2;
                l[i] += s;
                r[i] += s;
                self.phase += inc;
                if (self.phase >= TAU) self.phase -= TAU;
            }
        }

        // TODO(audio-ym): mix YM2149 output here
    }
};
