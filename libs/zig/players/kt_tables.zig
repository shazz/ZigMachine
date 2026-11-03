// --------------------------------------------------------------------------
// The .kt player's tables: upstream's own (music.c's vibrato shapes, cyd.c's
// envelope and YM curves) and the libm ones kt_tables_gen.zig holds exactly.
// --------------------------------------------------------------------------
const gen = @import("kt_tables_gen.zig");
const song = @import("kt_song.zig");

pub const frequency = gen.frequency;
pub const pan_left = gen.pan_left;
pub const pan_right = gen.pan_right;
pub const rvb_cos = gen.rvb_cos;
pub const rvb_sin = gen.rvb_sin;
pub const rvb_gain = gen.rvb_gain;
pub const rvb_low_limit = gen.rvb_low_limit;

/// freqs.c get_freq: the frequency (Hz * 16) of a note in 1/256 semitones,
/// interpolated between the table's semitones.
pub fn getFreq(note: i32) u16 {
    if (note <= 0) return frequency[0];
    if (note >= @as(i32, song.FREQ_TAB_SIZE) << 8) return frequency[song.FREQ_TAB_SIZE - 1];
    const i: usize = @intCast(note >> 8);
    if (note & 0xff == 0) return frequency[i];
    const f1: i32 = frequency[i];
    // Upstream reads frequency_table[96], one past the table, for the top semitone: the klystrack
    // cart has 0 there (apps/ports/klystrack/kt_ref/Makefile), so 0 it is.
    const f2: i32 = if (i + 1 < song.FREQ_TAB_SIZE) frequency[i + 1] else 0;
    return @intCast(f1 + @divTrunc((f2 - f1) * (note & 0xff), 256));
}

pub const LUT_SIZE = 1024;
pub const YM_LUT_SIZE = 16;

/// cyd_init_log_tables: the SID envelope's curve, i * (i / 2) / 8.
pub const env_lut: [LUT_SIZE]u16 = blk: {
    @setEvalBranchQuota(4 * LUT_SIZE);
    var t: [LUT_SIZE]u16 = undefined;
    for (0..LUT_SIZE) |i| t[i] = @intCast(i * (i / 2) / ((LUT_SIZE * LUT_SIZE / 65536) / 2));
    break :blk t;
};

/// The YM envelope's volume curve ("from leonard's code"), entry 0 forced to 0.
pub const ym_lut = [YM_LUT_SIZE]u16{ 0, 161, 265, 377, 580, 774, 1155, 1575, 2260, 3088, 4570, 6233, 9330, 13187, 21220, 32767 };

pub const VIB_TAB_SIZE = 128;

/// The LFO shapes' tables, as mus_init_engine builds them (kt_tables_gen.zig says how).
pub const rnd_table = gen.rnd_table;
pub const sine_table = gen.sine_table;

pub const SHAPE_SINE: u8 = 0;
pub const SHAPE_RAMP_UP: u8 = 1;
pub const SHAPE_RAMP_DN: u8 = 2;
pub const SHAPE_RANDOM: u8 = 3;
pub const SHAPE_SQUARE: u8 = 4;

/// music.c mus_shape: an LFO's value (-128..127) at `position`.
pub fn shape(position: u16, s: u8) i8 {
    const p: u16 = position % VIB_TAB_SIZE;
    return switch (s) {
        SHAPE_SINE => sine_table[p],
        SHAPE_SQUARE => if (p & (VIB_TAB_SIZE / 2) != 0) -128 else 127,
        SHAPE_RAMP_UP => @truncate(@as(i32, p) * 2 - 128),
        SHAPE_RAMP_DN => @truncate(127 - @as(i32, p) * 2),
        else => rnd_table[(position / 8) % VIB_TAB_SIZE],
    };
}
