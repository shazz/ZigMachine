// --------------------------------------------------------------------------
// cyd's envelopes (cyd_cycle_adsr, cyd_env_output): the SID-style ADSR and the
// YM2149-style buzz envelope, stepped once a sample, and the gain they put on
// a channel's oscillator sum. Signed divisions truncate toward zero, as C's.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const tab = @import("kt_tables.zig");
const set = @import("kt_cyd_set.zig");

/// One sample of the envelope; returns `flags` with GATE cleared when a
/// release runs out (unless a wavetable overrides the envelope).
pub inline fn cycle(rate: u32, flags: u32, shape: u8, a: *c.Adsr) u32 {
    if (flags & c.YM_ENV == 0) return sid(rate, flags, a);
    return ym(flags, shape, a);
}

fn releaseDone(flags: u32, a: *c.Adsr) u32 {
    a.state = c.DONE;
    a.envelope = 0;
    if (flags & (c.WAVE | c.WAVE_OVERRIDE_ENV) != (c.WAVE | c.WAVE_OVERRIDE_ENV)) return flags & ~c.GATE;
    return flags;
}

inline fn sid(rate: u32, flags: u32, a: *c.Adsr) u32 {
    switch (a.state) {
        c.ATTACK => {
            a.envelope +%= a.env_speed;
            if (a.envelope >= 0xff0000) {
                a.state = c.DECAY;
                a.envelope = 0xff0000;
                a.env_speed = set.envSpeed(rate, a.d);
            }
        },
        c.DECAY => {
            const sus: u32 = @as(u32, a.s) << 19;
            if (a.envelope > sus +% a.env_speed) {
                a.envelope -%= a.env_speed;
            } else {
                a.envelope = sus;
                a.state = if (a.s == 0) c.RELEASE else c.SUSTAIN;
                a.env_speed = set.envSpeed(rate, a.r);
            }
        },
        c.RELEASE => {
            if (a.envelope > a.env_speed) {
                a.envelope -%= a.env_speed;
            } else return releaseDone(flags, a);
        },
        else => {},
    }
    return flags;
}

inline fn ym(flags: u32, shape: u8, a: *c.Adsr) u32 {
    switch (a.state) {
        c.ATTACK => {
            a.envelope +%= a.env_speed;
            if (a.envelope >= c.YM_LENGTH) {
                if (shape & c.YM_ENV_ALT != 0) {
                    a.envelope = c.YM_LENGTH -% (a.envelope -% c.YM_LENGTH);
                    a.state = c.DECAY;
                } else {
                    a.envelope &= c.YM_LENGTH - 1;
                }
            }
        },
        c.DECAY => {
            if (a.envelope >= a.env_speed) {
                a.envelope -%= a.env_speed;
            } else if (shape & c.YM_ENV_ALT != 0) {
                a.envelope = a.env_speed -% a.envelope;
                a.state = c.ATTACK;
            } else {
                a.envelope -%= a.env_speed;
                a.envelope &= c.YM_LENGTH - 1;
            }
        },
        c.RELEASE => return releaseDone(flags, a),
        else => {},
    }
    return flags;
}

/// The envelope's gain on `input`, then the channel volume (0..128).
pub inline fn output(chn_flags: u32, a: *const c.Adsr, input: i32) i32 {
    const vol: i32 = a.volume;
    if (chn_flags & c.YM_ENV != 0) {
        const idx: u32 = a.envelope *% tab.YM_LUT_SIZE / c.YM_LENGTH;
        const g: i32 = tab.ym_lut[idx % tab.YM_LUT_SIZE];
        return @divTrunc(@divTrunc(input *% g, 32768) *% vol, 128);
    }
    // |input| < 2^15: input * a 16-bit gain fits 32 bits, and so does the volume's product, so the
    // Sint64 arithmetic below gives the same value in 32 (BARD's rv32 does 64-bit in several ops).
    if (input > -32768 and input < 32768) {
        const v32: i32 = if (a.state == c.ATTACK)
            @divTrunc(input * @divTrunc(@as(i32, @bitCast(a.envelope)), 0x10000), 256)
        else
            @divTrunc(input * @as(i32, tab.env_lut[(a.envelope / (65536 * 256 / tab.LUT_SIZE)) & (tab.LUT_SIZE - 1)]), 65536);
        return @divTrunc(v32 * vol, 128);
    }
    var v: i64 = undefined;
    if (a.state == c.ATTACK) {
        const e: i32 = @divTrunc(@as(i32, @bitCast(a.envelope)), 0x10000);
        v = @divTrunc(@as(i64, input) * e, 256);
    } else {
        const g: i64 = tab.env_lut[(a.envelope / (65536 * 256 / tab.LUT_SIZE)) & (tab.LUT_SIZE - 1)];
        v = @divTrunc(@as(i64, input) * g, 65536);
    }
    return @truncate(@divTrunc(v * vol, 128)); // upstream keeps the product in Sint64 to the end
}
