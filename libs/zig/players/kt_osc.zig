// --------------------------------------------------------------------------
// cyd's oscillators (cydosc.c, cyd.c cyd_advance_oscillators / run_lfsrs):
// pulse, saw, triangle, noise and the POKEY-style LFSR, combined by AND as
// cyd_osc's 31 cases are (every case is the AND of its waveforms), and the
// per-sample phase step with the noise register's shift and the sync bit.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");

const AMP_MASK: u32 = @as(u32, @intCast(c.WAVE_AMP)) - 1;

inline fn pulse(acc: u32, pw: u32) u32 {
    return if ((acc >> (c.ACC_BITS - 17)) >= (pw << 4)) AMP_MASK else 0;
}

inline fn saw(acc: u32) u32 {
    return (acc >> (c.ACC_BITS - c.OUTPUT_BITS - 1)) & AMP_MASK;
}

inline fn triangle(acc: u32) u32 {
    const v = if (acc & (c.ACC_LENGTH / 2) != 0) ~acc else acc;
    return (v >> (c.ACC_BITS - c.OUTPUT_BITS - 2)) & (AMP_MASK * 2 + 1);
}

/// cyd_osc: the waveforms `flags` selects at phase `acc`, ANDed; none selected is mid-scale.
pub inline fn osc(flags: u32, acc: u32, pw: u32, random: u32, lfsr_acc: u32) i32 {
    const sel = flags & c.WAVEFORMS & ~c.WAVE;
    if (sel == 0) return c.WAVE_AMP / 2;
    var v: u32 = 0xffffffff;
    if (sel & c.PULSE != 0) v &= pulse(acc, pw);
    if (sel & c.SAW != 0) v &= saw(acc);
    if (sel & c.TRIANGLE != 0) v &= triangle(acc);
    if (sel & c.NOISE != 0) v &= random & AMP_MASK;
    if (sel & c.LFSR != 0) v &= lfsr_acc;
    return @bitCast(v);
}

/// lfsr-generator's Galois shift with taps `t0` and `t1`.
pub inline fn shift(v: *u32, comptime t0: u5, comptime t1: u5) void {
    const fb: u32 = (@as(u32, 1) << t0) ^ (@as(u32, 1) << t1);
    v.* = (v.* >> 1) ^ ((0 -% (v.* & 1)) & fb);
}

inline fn runLfsrs(ch: *c.Channel) void {
    inline for (&ch.subosc) |*o| {
        shift(&o.reg4, 4, 3);
        shift(&o.reg5, 5, 3);
        if (ch.lfsr_type & 8 != 0) shift(&o.reg9, 9, 5) else shift(&o.reg9, 17, 14);
    }
}

/// cyd_advance_oscillators: one sample of every sub-oscillator's phase (of those `subs` names: the
/// others are idle, kt_block.zig).
pub inline fn advance(ch: *c.Channel, comptime subs: u3) void {
    const lfsr = ch.flags & c.LFSR != 0;
    // Frequency 0: the phase stays (it is kept below ACC_LENGTH), so no sync bit and no noise step;
    // only the LFSR, when on, still moves.
    inline for (&ch.subosc, 0..) |*o, s| if (subs >> s & 1 != 0 and (o.frequency != 0 or lfsr)) step(ch, o, s == 0);
}

/// `n` samples of advance for a channel nobody hears the oscillators of and with no LFSR: each
/// sub-oscillator on its own (no LFSR: they share nothing), its phase and noise in locals; the sync
/// bit left as the last sample's.
pub fn advanceN(ch: *c.Channel, n: usize, comptime subs: u3) void {
    const metal = ch.flags & c.METAL != 0;
    ch.sync_bit = 0;
    inline for (&ch.subosc, 0..) |*o, s| if (subs >> s & 1 != 0 and o.frequency != 0) {
        var acc = o.accumulator;
        var random = o.random;
        const freq = o.frequency;
        var sync: u32 = 0;
        for (0..n) |_| {
            const prev = acc;
            acc +%= freq;
            sync = acc & c.ACC_LENGTH;
            acc &= c.ACC_LENGTH - 1;
            if ((prev ^ acc) & (c.ACC_LENGTH / 32) != 0) {
                if (metal) {
                    shift(&random, 0xe, 8);
                    random &= (1 << (0xe + 1)) - 1;
                } else {
                    shift(&random, 22, 17);
                    random &= (1 << (22 + 1)) - 1;
                }
            }
        }
        o.accumulator = acc;
        o.random = random;
        if (s == 0) ch.sync_bit = sync;
    };
}

/// The sync bit `ch` leaves after each of its next `n` samples (its first sub-oscillator's wrap), for
/// a channel whose phase nothing resets meanwhile: out[t] = 1 where sample t wraps.
pub fn syncBits(ch: *const c.Channel, n: usize, out: [*]u8) void {
    const o = &ch.subosc[0];
    if (o.frequency == 0) return @memset(out[0..n], 0); // no step, or a step of 0: never a wrap
    var acc = o.accumulator;
    for (0..n) |t| {
        acc +%= o.frequency;
        out[t] = @intFromBool(acc & c.ACC_LENGTH != 0);
        acc &= c.ACC_LENGTH - 1;
    }
}

inline fn step(ch: *c.Channel, o: *c.Osc, comptime first: bool) void {
    const prev = o.accumulator;
    o.accumulator +%= o.frequency;
    if (first) ch.sync_bit |= o.accumulator & c.ACC_LENGTH;
    o.accumulator &= c.ACC_LENGTH - 1;
    if ((prev & (c.ACC_LENGTH / 32)) != (o.accumulator & (c.ACC_LENGTH / 32))) {
        if (ch.flags & c.METAL != 0) {
            shift(&o.random, 0xe, 8);
            o.random &= (1 << (0xe + 1)) - 1;
        } else {
            shift(&o.random, 22, 17);
            o.random &= (1 << (22 + 1)) - 1;
        }
    }
    if (ch.flags & c.LFSR != 0) lfsrStep(ch, o);
}

inline fn lfsrStep(ch: *c.Channel, o: *c.Osc) void {
    o.lfsr_acc = if (o.lfsr & 1 != 0) AMP_MASK else 0;
    if (o.lfsr_ctr >= o.lfsr_period) {
        o.lfsr_ctr = 0;
        const bit: u32 = switch (ch.lfsr_type & 3) {
            0 => o.reg5 & o.reg9 & 1,
            1, 3 => o.reg5 & 1,
            else => o.reg5 & o.reg4 & 1, // 2
        };
        o.lfsr ^= bit;
    }
    o.lfsr_ctr +%= 1;
    runLfsrs(ch);
}
