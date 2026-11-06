// --------------------------------------------------------------------------
// cyd's wavetable voice (cydwave.c, LOWRESWAVETABLE: a Uint32 phase in 1/2048
// sample): the sample read (linear or nearest) and the per-sample phase step
// with forward and ping-pong loops.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");

const RES = c.WAVETABLE_RESOLUTION;
const IRES: i32 = RES;

/// What a block knows of a wave entry for its whole length (its flags, and whether its loop is
/// empty): the sample read and the phase step built for it (kt_passes.zig), the branches gone.
/// null: read the entry's flags each time (the per-sample path).
pub const Shape = struct { interp: bool, loop: bool, pingpong: bool, looped: bool };

pub fn shapeCode(e: *const song.WaveEntry) u4 {
    const lp = e.flags & song.WAVE_LOOP != 0;
    return @as(u4, @intFromBool(e.flags & song.WAVE_NO_INTERPOLATION == 0)) | @as(u4, @intFromBool(lp)) << 1 |
        @as(u4, @intFromBool(e.flags & song.WAVE_PINGPONG != 0)) << 2 | @as(u4, @intFromBool(lp and e.loop_end != e.loop_begin)) << 3;
}

pub fn shape(comptime code: u4) Shape {
    return .{ .interp = code & 1 != 0, .loop = code & 2 != 0, .pingpong = code & 4 != 0, .looped = code & 8 != 0 };
}

inline fn interp(e: *const song.WaveEntry, comptime s: ?Shape) bool {
    return if (s) |k| k.interp else e.flags & song.WAVE_NO_INTERPOLATION == 0;
}
inline fn hasLoop(e: *const song.WaveEntry, comptime s: ?Shape) bool {
    return if (s) |k| k.loop else e.flags & song.WAVE_LOOP != 0;
}
inline fn pingpong(e: *const song.WaveEntry, comptime s: ?Shape) bool {
    return if (s) |k| k.pingpong else e.flags & song.WAVE_PINGPONG != 0;
}
inline fn looped(e: *const song.WaveEntry, comptime s: ?Shape) bool {
    return if (s) |k| k.looped else e.flags & song.WAVE_LOOP != 0 and e.loop_end != e.loop_begin;
}

pub inline fn sample(st: *const c.WaveState, e: *const song.WaveEntry, acc: u32) i32 {
    return sampleS(st, e, acc, null);
}

pub inline fn sampleS(st: *const c.WaveState, e: *const song.WaveEntry, acc: u32, comptime s: ?Shape) i32 {
    const data = e.data orelse return 0;
    if (!interp(e, s)) return data[acc / RES];
    const a: i32 = @intCast(acc / RES); // < 2^21: never negative
    if (a >= e.samples) return 0;
    const da: i32 = data[@intCast(a)];
    // (CydWaveAccSigned)acc % RES: acc / RES < e.samples <= 2^20 here (kt_load_parts.zig refuses
    // more), so acc < 2^31 is positive as a signed value and its remainder is its low bits.
    const frac: i32 = @intCast(acc & (RES - 1));
    if (st.direction == 0) {
        var b = a + 1;
        if (hasLoop(e, s) and b >= e.loop_end) {
            const le: i32 = @intCast(e.loop_end);
            b = if (!pingpong(e, s)) b - le + @as(i32, @intCast(e.loop_begin)) else le - (b - le);
        }
        if (b >= e.samples) return da;
        return da + @divTrunc((@as(i32, data[@intCast(b)]) - da) * frac, IRES);
    }
    var b = a - 1;
    const lb: i32 = @intCast(e.loop_begin);
    if (hasLoop(e, s) and b < lb) {
        b = if (!pingpong(e, s)) b - lb + @as(i32, @intCast(e.loop_end)) else lb - (b - lb);
    }
    if (b < 0) return da;
    return da + @divTrunc((@as(i32, data[@intCast(b)]) - da) * (IRES - frac), IRES);
}

/// cyd_wave_cycle: one sample of the wavetable phase.
pub inline fn cycle(w: *c.WaveState, entry: ?*const song.WaveEntry) void {
    const e = entry orelse return;
    cycleS(w, e, null);
}

pub inline fn cycleS(w: *c.WaveState, e: *const song.WaveEntry, comptime s: ?Shape) void {
    if (!w.playing) return;
    const lp = looped(e, s);
    // Upstream's (Uint64) loop products land in a Uint32 acc: the same value mod 2^32, in 32 bits.
    const lb: u32 = e.loop_begin *% RES;
    const le: u32 = e.loop_end *% RES;
    if (w.direction == 0) {
        // At frequency 0 (a sub-oscillator the note leaves unused) the phase stays where it is.
        if (w.frequency == 0 and w.acc / RES < (if (lp) e.loop_end else e.samples)) return;
        w.acc +%= w.frequency;
        if (lp) {
            if (w.acc / RES >= e.loop_end) {
                if (pingpong(e, s)) {
                    w.acc = le -% (w.acc -% le);
                    w.direction = 1;
                } else w.acc = w.acc -% le +% lb;
            }
        } else if (w.acc / RES >= e.samples) w.playing = false;
        return;
    }
    w.acc -%= w.frequency;
    if (lp) {
        const sacc: i32 = @bitCast(w.acc);
        if (@divTrunc(sacc, IRES) < @as(i32, @bitCast(e.loop_begin))) {
            if (pingpong(e, s)) {
                const slb: i32 = @bitCast(lb);
                w.acc = @bitCast(slb -% (sacc -% slb));
                w.direction = 0;
            } else w.acc = w.acc -% lb +% le;
        }
    } else if (@as(i32, @bitCast(w.acc)) < 0) w.playing = false;
}
