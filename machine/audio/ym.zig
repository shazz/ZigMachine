const std = @import("std");

// --------------------------------------------------------------------------
// YM2149 (Atari ST PSG) emulator — a MACHINE primitive.
//
// 3 square-wave tone channels + noise + a 32-step envelope generator, driven by
// 14 registers exactly like the real chip. A ZigOS player (ym_player.zig) writes
// registers 50 times/second from a YM register dump; render() turns the chip
// state into audio. Output is mono (as on a real ST) written to both channels.
// --------------------------------------------------------------------------

pub const YM_CLOCK: f32 = 2000000.0; // Atari ST PSG clock (2 MHz)

// The DAC: the YM2149's 32 output levels (5 bits), normalised to 1.0 at level 31.
// The envelope indexes all 32; a fixed 4-bit volume v uses level 2*v+1.
//
// The curve is the datasheet's logarithmic one (about 3 dB a volume step, half
// that an envelope step) with a small offset that pulls the bottom to zero:
//     amp(L) = (10^(DB_STEP * (L - 31) / 20) - FLOOR) / (1 - FLOOR),  L >= 2
// DB_STEP and FLOOR are fitted to Paulo Simoes's 2012 measurement of a real ST
// (one channel; published with Hatari, src/includes/ym2149_fixed_vol.h): every
// fixed volume 1..15 is within 1.03 dB of it (ym_dac_test.zig). A pure log curve
// is 7 dB off at volume 1; the table used before this (an AY-style curve) was up
// to 7.8 dB too quiet at volumes 2..8. jotego's jt49 (the FPGA's YM) is within
// 1.6 dB of the measurement and within 2 dB of this curve.
//
// Channels are summed linearly. A real ST compresses the sum (three channels at
// 15 are +5.5 dB over one, not +9.5): against the measured 16x16x16 table a
// linear sum of this curve is within 0.95 dB for half the combinations and
// 1.74 dB for 90 %, 4.0 dB at worst (all three at 15). Linear is kept: it is
// what the FPGA's mixer does, and only loud chords are affected
// (decisions.md, "The YM DAC curve and envelope hold").
pub const DB_STEP: f64 = 1.6025;
pub const FLOOR: f64 = 0.0018;
pub const VOL_TABLE = blk: {
    @setEvalBranchQuota(10000);
    var t: [32]f32 = undefined;
    for (&t, 0..) |*a, l| {
        const db = DB_STEP * (@as(f64, @floatFromInt(l)) - 31.0);
        const amp = (std.math.pow(f64, 10.0, db / 20.0) - FLOOR) / (1.0 - FLOOR);
        a.* = if (l <= 1) 0.0 else @floatCast(amp);
    }
    break :blk t;
};

pub const Ym2149 = struct {
    regs: [16]u8 = [_]u8{0} ** 16,
    sr: f32 = 44100.0,

    tone_phase: [3]f32 = .{ 0, 0, 0 },
    noise_acc: f32 = 0,
    noise_lfsr: u17 = 1,
    noise_bit: u1 = 0,

    env_acc: f32 = 0,
    env_pos: u5 = 0,
    env_attack: bool = false,
    env_cont: bool = false,
    env_alt: bool = false,
    env_hold: bool = false,
    env_holding: bool = false,

    pub fn init(self: *Ym2149, sample_rate: f32) void {
        self.* = .{ .sr = sample_rate, .noise_lfsr = 1 };
    }

    pub fn writeReg(self: *Ym2149, reg: u8, value: u8) void {
        const r = reg & 0x0F;
        self.regs[r] = value;
        // Writing the shape register retriggers the envelope (0xFF = "no change").
        if (reg == 13 and value != 0xFF) self.envReset(value);
    }

    fn envReset(self: *Ym2149, shape: u8) void {
        self.env_attack = (shape & 0x04) != 0;
        self.env_alt = (shape & 0x02) != 0;
        self.env_cont = (shape & 0x08) != 0;
        self.env_hold = (shape & 0x01) != 0;
        self.env_holding = false;
        self.env_pos = if (self.env_attack) 0 else 31;
    }

    pub fn envStep(self: *Ym2149) void {
        if (self.env_holding) return;
        if (self.env_attack) {
            if (self.env_pos < 31) {
                self.env_pos += 1;
                return;
            }
        } else {
            if (self.env_pos > 0) {
                self.env_pos -= 1;
                return;
            }
        }
        // reached end of a ramp
        if (!self.env_cont) {
            self.env_pos = 0;
            self.env_holding = true;
            return;
        }
        if (self.env_hold) {
            // HOLD takes the ALTERNATED level when ALT is set (datasheet): 11
            // (\---) decays then holds high, 15 (/___) attacks then holds low.
            if (self.env_alt) self.env_pos = 31 - self.env_pos;
            self.env_holding = true;
            return;
        }
        if (self.env_alt) self.env_attack = !self.env_attack;
        self.env_pos = if (self.env_attack) 0 else 31;
    }

    fn tonePeriod(self: *Ym2149, ch: usize) u32 {
        const fine: u32 = self.regs[ch * 2];
        const coarse: u32 = self.regs[ch * 2 + 1] & 0x0F;
        const p = (coarse << 8) | fine;
        return if (p == 0) 1 else p;
    }

    /// Channel ch's tone gate for this output sample: 1 open, 0 shut, or 0.5
    /// for a tone above the output's Nyquist frequency. Periods 0-5 (125 kHz
    /// down to 25 kHz on the ST's 2 MHz clock) cannot be sampled at 44.1 kHz:
    /// point-sampled, 125 kHz folds down to |125000 - 3 * 44100| = 7300 Hz, a
    /// loud whistle no ST makes. The chip's output (and Hatari's 250 kHz
    /// model, filtered down) is that square's average: open half the time.
    /// Digis (a volume per sample, tone period 0 left on) and STOS's engine
    /// noise (mixer $C0, periods 0) rely on exactly that.
    pub fn toneGate(self: *Ym2149, ch: usize, mixer: u8) f32 {
        const period: f32 = @floatFromInt(self.tonePeriod(ch));
        const step = (YM_CLOCK / (16.0 * period)) / self.sr;
        self.tone_phase[ch] += step;
        if (self.tone_phase[ch] >= 1.0) self.tone_phase[ch] -= @floor(self.tone_phase[ch]);
        if ((mixer >> @intCast(ch)) & 1 == 1) return 1;
        if (step > 0.5) return 0.5;
        return if (self.tone_phase[ch] < 0.5) 1 else 0;
    }

    pub fn render(self: *Ym2149, left: []f32, right: []f32) void {
        const n = left.len;
        const mixer = self.regs[7];

        var i: usize = 0;
        while (i < n) : (i += 1) {
            // advance noise
            const np: f32 = @floatFromInt(@max(@as(u8, 1), self.regs[6] & 0x1F));
            self.noise_acc += (YM_CLOCK / (16.0 * np)) / self.sr;
            while (self.noise_acc >= 1.0) {
                self.noise_acc -= 1.0;
                // 17-bit LFSR, taps 0 and 3
                const bit: u1 = @truncate((self.noise_lfsr ^ (self.noise_lfsr >> 3)));
                self.noise_lfsr = (self.noise_lfsr >> 1) | (@as(u17, bit) << 16);
                self.noise_bit = @truncate(self.noise_lfsr);
            }

            // Advance the envelope. clock/(256*EP) is the frequency of a COMPLETE
            // 32-step envelope, so one STEP comes 32 times as often — clock/(8*EP).
            // Getting this wrong runs the envelope 32x slow, which is inaudible on
            // a long sweep but silences the buzzer bass the ST is known for: a
            // replay that retriggers r13 every 50 Hz frame (as most do) never gets
            // past the first step or two of the ramp.
            const ep: f32 = @floatFromInt(@max(@as(u16, 1), (@as(u16, self.regs[12]) << 8) | self.regs[11]));
            self.env_acc += (YM_CLOCK / (8.0 * ep)) / self.sr;
            while (self.env_acc >= 1.0) {
                self.env_acc -= 1.0;
                self.envStep();
            }
            var mix: f32 = 0;
            var ch: usize = 0;
            while (ch < 3) : (ch += 1) {
                const t = self.toneGate(ch, mixer);
                const noise_off = (mixer >> @intCast(ch + 3)) & 1 == 1;
                const nz = (self.noise_bit == 1) or noise_off;
                if (t > 0 and nz) {
                    const vreg = self.regs[8 + ch];
                    // envelope uses the full 5-bit level; fixed 4-bit v -> 2*v+1
                    const level: u5 = if (vreg & 0x10 != 0)
                        self.env_pos
                    else
                        @intCast(@as(u8, vreg & 0x0F) * 2 + 1);
                    mix += VOL_TABLE[level] * t;
                }
            }
            const out = mix * 0.33; // headroom for 3 channels summed
            left[i] += out;
            right[i] += out;
        }
    }
};
