// --------------------------------------------------------------------------
// cyd's FM modulator (cydfm.c): a triangle or a wavetable voice with its own
// envelope and feedback, whose output shifts the carrier's phase. Upstream's
// widths: CydWaveAcc products wrap at 32 bits (LOWRESWAVETABLE), the
// (Uint64) ones do not.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const adsr = @import("kt_adsr.zig");
const wave = @import("kt_wave.zig");
const osc = @import("kt_osc.zig");

const MODULATOR_MAX: u32 = 1024;
const fb_shift = [8]u5{ 0, 6, 5, 4, 3, 2, 1, 0 }; // log2 of fbtab {0, 64, 32, 16, 8, 4, 2, 1}

/// x % e.span with no divide (BARD has none: a `%` is a libgcc loop): q from the precomputed
/// 2^32 / span is the quotient or one or two short, so the remainder is exact after at most two
/// subtractions.
inline fn modSpan(x: u32, e: *const song.WaveEntry) u32 {
    if (x < e.span) return x;
    if (e.span <= 1) return 0; // span 1: everything is 0 mod 1 (span 0 never reaches here)
    const q: u32 = @intCast((@as(u64, x) * e.span_inv) >> 32);
    var r = x -% q *% e.span;
    while (r >= e.span) r -= e.span;
    return r;
}

/// The feedback term: (Uint64)(fb1 + fb2) / 2 * (span * 4 / fbtab[feedback]) / MODULATOR_MAX.
inline fn feedback(fm: *const c.Fm, span: u32) u32 {
    const fbsum: u64 = fm.fb1 +% fm.fb2;
    const k: u64 = (span *% 4) >> fb_shift[fm.feedback];
    return @truncate(fbsum / 2 * k / MODULATOR_MAX);
}

fn modulator(fm: *const c.Fm) u32 {
    if (fm.flags & c.WAVE != 0) if (fm.wave_entry) |e| {
        const length = e.span;
        if (length == 0) return 0;
        var acc = fm.wave.acc;
        if (fm.feedback != 0) acc +%= feedback(fm, length);
        const smp: i64 = wave.sample(&fm.wave, e, modSpan(acc, e));
        return @truncate(@as(u64, @bitCast(@divTrunc(smp * fm.env_output, 32768) + 65536)));
    };
    var acc = fm.accumulator;
    if (fm.feedback != 0) acc +%= feedback(fm, c.ACC_LENGTH);
    const tri: u64 = @as(u32, @bitCast(osc.osc(c.TRIANGLE, acc % c.ACC_LENGTH, 0, 0, 0)));
    return @truncate(tri * fm.env_output / @as(u32, @intCast(c.WAVE_AMP)) + @as(u32, @intCast(c.WAVE_AMP / 2)));
}

/// cydfm_cycle: one sample of the modulator.
pub fn cycle(rate: u32, fm: *c.Fm) void {
    _ = adsr.cycle(rate, 0, 0, &fm.adsr);
    fm.env_output = @bitCast(adsr.output(0, &fm.adsr, MODULATOR_MAX));
    wave.cycle(&fm.wave, fm.wave_entry);
    fm.accumulator = (fm.accumulator +% fm.period) % c.ACC_LENGTH;
    const m = modulator(fm);
    fm.fb2 = fm.fb1;
    fm.fb1 = m;
    fm.current_modulation = m;
}

/// cydfm_modulate(cyd, fm, 0): the carrier's phase offset.
pub fn modulate(fm: *const c.Fm) u32 {
    const m: u32 = @truncate(@as(u64, fm.current_modulation) * c.ACC_LENGTH * 8 / MODULATOR_MAX);
    return m % c.ACC_LENGTH;
}

/// cydfm_modulate_wave: a wavetable carrier's phase, offset within its loop.
pub fn modulateWave(fm: *const c.Fm, e: *const song.WaveEntry, acc: u32) u32 {
    if (e.loop_begin == e.loop_end) return acc;
    const length = e.span;
    if (length == 0) return 0; // upstream divides by 0 here: a loop of 2^21 samples; never in a real song
    const m: u32 = (fm.current_modulation *% length *% 8) / MODULATOR_MAX;
    return modSpan(m +% acc, e);
}
