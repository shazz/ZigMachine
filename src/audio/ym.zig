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

// YM2149 has a 32-level (5-bit) DAC. Measured curve (MAME/AY), normalized to 1.0.
// The envelope indexes all 32 levels; a fixed 4-bit volume v uses level 2*v+1.
const VOL_TABLE = blk: {
    const raw = [32]f32{
        0.0,     0.0,     0.00465, 0.00658, 0.00785, 0.00932, 0.01180, 0.01393,
        0.01895, 0.02233, 0.02988, 0.03535, 0.04697, 0.05532, 0.07322, 0.08659,
        0.11498, 0.13584, 0.18018, 0.21287, 0.28281, 0.33417, 0.44399, 0.52471,
        0.68753, 0.81095, 1.06210, 1.25389, 1.65437, 1.95431, 2.58200, 3.05064,
    };
    var t: [32]f32 = undefined;
    const maxv = raw[31];
    for (raw, 0..) |v, i| t[i] = v / maxv;
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

    fn envStep(self: *Ym2149) void {
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

            // advance envelope
            const ep: f32 = @floatFromInt(@max(@as(u16, 1), (@as(u16, self.regs[12]) << 8) | self.regs[11]));
            self.env_acc += (YM_CLOCK / (256.0 * ep)) / self.sr;
            while (self.env_acc >= 1.0) {
                self.env_acc -= 1.0;
                self.envStep();
            }
            var mix: f32 = 0;
            var ch: usize = 0;
            while (ch < 3) : (ch += 1) {
                const period: f32 = @floatFromInt(self.tonePeriod(ch));
                self.tone_phase[ch] += (YM_CLOCK / (16.0 * period)) / self.sr;
                if (self.tone_phase[ch] >= 1.0) self.tone_phase[ch] -= @floor(self.tone_phase[ch]);
                const tone_high = self.tone_phase[ch] < 0.5;

                const tone_off = (mixer >> @intCast(ch)) & 1 == 1;
                const noise_off = (mixer >> @intCast(ch + 3)) & 1 == 1;
                const t = tone_high or tone_off;
                const nz = (self.noise_bit == 1) or noise_off;
                if (t and nz) {
                    const vreg = self.regs[8 + ch];
                    // envelope uses the full 5-bit level; fixed 4-bit v -> 2*v+1
                    const level: u5 = if (vreg & 0x10 != 0)
                        self.env_pos
                    else
                        @intCast(@as(u8, vreg & 0x0F) * 2 + 1);
                    mix += VOL_TABLE[level];
                }
            }
            const out = mix * 0.33; // headroom for 3 channels summed
            left[i] += out;
            right[i] += out;
        }
    }
};
