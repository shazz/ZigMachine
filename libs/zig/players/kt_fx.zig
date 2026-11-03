// --------------------------------------------------------------------------
// cyd's FX buses (cydfx.c, cydrvb.c, cydcrush.c): chorus (kt_chorus.zig), a
// 16-tap delay reverb with no feedback, and a bit crusher, in upstream's
// order. The reverb reads each tap at "write position minus delay" (the
// klystrack cart's cydrvb.c.sed): the same sample as upstream's 16 moving tap
// positions, without the 16 increments. Its line is mono: upstream writes the
// bus's left input to both halves (cydfx_output: cydrvb_cycle(fx_l, fx_l)).
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const tab = @import("kt_tables.zig");
const chorus = @import("kt_chorus.zig");

pub const RVB_MS = 2000; // CYDRVB_SIZE

pub const Tap = struct { gain_l: i32 = 0, gain_r: i32 = 0, delay: u32 = 0 };

pub const Reverb = struct {
    line: []i32 = &.{}, // 2 s of the bus's left input
    position: u32 = 0,
    taps: [song.RVB_TAPS]Tap = [_]Tap{.{}} ** song.RVB_TAPS,
    n_taps: u8 = 0, // taps with a gain, packed first
};

pub const Crush = struct {
    counter: i32 = 0,
    bit_drop: u32 = 0,
    downsample: i32 = 0,
    dither: bool = false,
    gain: i32 = 128,
    hold_l: i32 = 0,
    hold_r: i32 = 0,
    error_l: i32 = 0,
    error_r: i32 = 0,
};

pub const Bus = struct {
    flags: u32 = 0,
    in_l: i32 = 0, // this sample's input, summed from its channels (kt_synth.zig), cleared as read
    in_r: i32 = 0,
    rvb: Reverb = .{},
    chr: chorus.Chorus = .{},
    crush: Crush = .{},
};

/// cydrvb_set_tap for every tap of `def` (float at load only: upstream's
/// pow/cos/sin are tables, the int x double product is IEEE-exact here too).
/// A gain above 0 dB is not in the table: the caller refuses such a song.
pub fn setTaps(r: *Reverb, def: *const song.FxDef, rate: u32) void {
    r.n_taps = 0;
    const size: u32 = @intCast(r.line.len);
    for (def.taps) |t| {
        const g: i32 = t.gain;
        if (t.flags & 1 == 0 or g <= tab.rvb_low_limit or g > 0 or size == 0) continue;
        const gain: f64 = @floatFromInt(tab.rvb_gain[@intCast(g - tab.rvb_low_limit - 1)]);
        const p: usize = @min(t.panning, 128);
        const tap = Tap{
            .gain_l = @intFromFloat(gain * tab.rvb_cos[p]),
            .gain_r = @intFromFloat(gain * tab.rvb_sin[p]),
            .delay = @min(@as(u32, t.delay) * rate / 1000, size) % size,
        };
        if (tap.gain_l == 0 and tap.gain_r == 0) continue; // cydrvb_output skips it
        r.taps[r.n_taps] = tap;
        r.n_taps += 1;
    }
}

/// cydcrush_set: -1 keeps a field.
pub fn setCrush(k: *Crush, rate: u32, downsample: i32, bit_drop: i32, dither: i32, gain: i32) void {
    k.downsample = @divTrunc(downsample * @as(i32, @intCast(rate)), 44100);
    if (bit_drop >= 0) k.bit_drop = if (bit_drop >= 32) 0 else @as(u32, 0xffffffff) << @intCast(bit_drop);
    if (dither >= 0) k.dither = dither != 0;
    if (gain >= 0) k.gain = gain;
}

inline fn reverb(r: *Reverb, in: i32, l: *i32, rr: *i32) void {
    const size: u32 = @intCast(r.line.len);
    r.position += 1;
    if (r.position >= size) r.position = 0;
    r.line[r.position] = in;
    var sl: i32 = 0;
    var sr: i32 = 0;
    for (r.taps[0..r.n_taps]) |t| {
        const at = if (r.position >= t.delay) r.position - t.delay else r.position + size - t.delay;
        const v = r.line[at];
        sl +%= @divTrunc(t.gain_l *% v, 2048);
        sr +%= @divTrunc(t.gain_r *% v, 2048);
    }
    l.* +%= sl;
    rr.* +%= sr;
}

inline fn crushOne(k: *Crush, in: i32, err: *i32) i32 {
    const mask: i32 = @bitCast(k.bit_drop);
    if (!k.dither) return ((in +% 32768) & mask) -% 32768;
    const h = (@max(0, @min(65535, in +% 32768 +% err.*)) & mask) -% 32768;
    err.* +%= in -% h;
    return h;
}

inline fn crush(k: *Crush, l: *i32, r: *i32) void {
    const was = k.counter;
    k.counter +%= 1;
    if (was >= k.downsample) {
        k.counter = 0;
        k.hold_l = crushOne(k, l.*, &k.error_l);
        k.hold_r = crushOne(k, r.*, &k.error_r);
    }
    l.* = @divTrunc(k.hold_l *% k.gain, 128);
    r.* = @divTrunc(k.hold_r *% k.gain, 128);
}

/// cydfx_output: the bus's input (`l`, `r`) in, its output out.
pub fn output(b: *Bus, l: *i32, r: *i32) void {
    const in_l = l.*;
    const in_r = r.*;
    if (b.flags & song.FX_CHORUS != 0) chorus.output(&b.chr, in_l, in_r, l, r);
    if (b.flags & song.FX_REVERB != 0 and b.rvb.line.len != 0) reverb(&b.rvb, in_l, l, r);
    if (b.flags & song.FX_CRUSH != 0) crush(&b.crush, l, r);
}
