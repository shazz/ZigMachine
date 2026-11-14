// --------------------------------------------------------------------------
// The MP3 player's output (mp3.zig): a 16-bit stereo sample as four Paula
// bytes, hi L, hi R, lo L, lo R, with 128 h + l = x >> 1 a side (the hi
// channel at VOL 256, the lo at VOL 2: exact on the RTL and the engine,
// fpga/tests/hilo_probe.py), into the xm_ring spans kt.zig uses; and the
// status word zg.mp3Status(0) reads.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");

pub const VOL_HI: f32 = 1.0; // VOL 256
pub const VOL_LO: f32 = 2.0 / 256.0; // VOL 2
const PAN = [audio.NUM_CHANNELS]f32{ -1.0, 1.0, -1.0, 1.0 };

pub fn setup() void {
    for (0..audio.NUM_CHANNELS) |ch| {
        audio.machinePaulaSetStep(@intCast(ch), 1 << 16);
        audio.machinePaulaSetVolume(@intCast(ch), if (ch < 2) VOL_HI else VOL_LO);
    }
    audio.machinePaulaClearScopes();
}

pub const Bufs = [audio.NUM_CHANNELS][*]i8;

pub fn buffers(at0: u32) Bufs {
    var b: Bufs = undefined;
    for (&b, 0..) |*p, ch| p.* = @ptrFromInt(audio.SONG_BASE + chip.BUF_OFFSET + ch * ring.FRAMES + at0);
    return b;
}

/// A sample's four channel bytes: y = x >> 1 = 128 h + l, h in -128..127, l in -64..63. The top 64 values of
/// y (x >= 32640) have no h: they hold at 127 x 128 + 63 (they wrapped to -128 x 128 before: a full-scale
/// positive sample played as full-scale negative).
pub const Y_MAX: i32 = 127 * 128 + 63;
pub inline fn bytes(smp: [2]i16) [audio.NUM_CHANNELS]i8 {
    var b: [audio.NUM_CHANNELS]i8 = undefined;
    for (0..2) |side| {
        const y: i32 = @min(@as(i32, smp[side]) >> 1, Y_MAX);
        const h = (y + 64) >> 7;
        b[side] = @intCast(h);
        b[2 + side] = @intCast(y - (h << 7));
    }
    return b;
}

pub inline fn put(bufs: Bufs, f: u32, b: [audio.NUM_CHANNELS]i8) void {
    for (0..audio.NUM_CHANNELS) |ch| bufs[ch][f] = b[ch];
}

pub fn trigger(at0: u32, n: u32) void {
    for (0..audio.NUM_CHANNELS) |ch| {
        const at = chip.BUF_OFFSET + ch * ring.FRAMES + at0;
        audio.machinePaulaTrigger(@intCast(ch), audio.songAddr(at), n, 0, 0, PAN[ch]);
    }
}

/// zg.mp3Status(0): bits 0-1 the state (0 idle, 1 playing, 2 paused, 3 ended), bit 2 the input has
/// ended, bits 4-7 the rate (0 none yet, 1 32 kHz, 2 44.1, 3 48, 4 another), bit 8 stereo, bits 16-23
/// decode errors and 24-31 underruns (both saturate at 255).
pub fn word(state: u32, eof: bool, rate: u32, stereo: bool, errors: u32, underruns: u32) u32 {
    const code: u32 = switch (rate) {
        0 => 0,
        32000 => 1,
        44100 => 2,
        48000 => 3,
        else => 4,
    };
    return state | (@as(u32, @intFromBool(eof)) << 2) | (code << 4) | (@as(u32, @intFromBool(stereo)) << 8) |
        (@as(u32, @min(errors, 255)) << 16) | (@as(u32, @min(underruns, 255)) << 24);
}
