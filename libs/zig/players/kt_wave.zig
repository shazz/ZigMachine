// --------------------------------------------------------------------------
// cyd's wavetable voice (cydwave.c, LOWRESWAVETABLE: a Uint32 phase in 1/2048
// sample): the sample read (linear or nearest) and the per-sample phase step
// with forward and ping-pong loops.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");

const RES = c.WAVETABLE_RESOLUTION;
const IRES: i32 = RES;

pub inline fn sample(st: *const c.WaveState, e: *const song.WaveEntry, acc: u32) i32 {
    const data = e.data orelse return 0;
    if (e.flags & song.WAVE_NO_INTERPOLATION != 0) return data[acc / RES];
    const a: i32 = @intCast(acc / RES);
    if (a >= e.samples or a < 0) return 0;
    const da: i32 = data[@intCast(a)];
    const frac: i32 = @rem(@as(i32, @bitCast(acc)), IRES); // (CydWaveAccSigned)acc % RES
    if (st.direction == 0) {
        var b = a + 1;
        if (e.flags & song.WAVE_LOOP != 0 and b >= e.loop_end) {
            const le: i32 = @intCast(e.loop_end);
            b = if (e.flags & song.WAVE_PINGPONG == 0) b - le + @as(i32, @intCast(e.loop_begin)) else le - (b - le);
        }
        if (b >= e.samples) return da;
        return da + @divTrunc((@as(i32, data[@intCast(b)]) - da) * frac, IRES);
    }
    var b = a - 1;
    const lb: i32 = @intCast(e.loop_begin);
    if (e.flags & song.WAVE_LOOP != 0 and b < lb) {
        b = if (e.flags & song.WAVE_PINGPONG == 0) b - lb + @as(i32, @intCast(e.loop_end)) else lb - (b - lb);
    }
    if (b < 0) return da;
    return da + @divTrunc((@as(i32, data[@intCast(b)]) - da) * (IRES - frac), IRES);
}

/// cyd_wave_cycle: one sample of the wavetable phase.
pub inline fn cycle(w: *c.WaveState, entry: ?*const song.WaveEntry) void {
    const e = entry orelse return;
    if (!w.playing) return;
    const looped = e.flags & song.WAVE_LOOP != 0 and e.loop_end != e.loop_begin;
    const lb: u64 = @as(u64, e.loop_begin) * RES;
    const le: u64 = @as(u64, e.loop_end) * RES;
    if (w.direction == 0) {
        w.acc +%= w.frequency;
        if (looped) {
            if (w.acc / RES >= e.loop_end) {
                if (e.flags & song.WAVE_PINGPONG != 0) {
                    w.acc = @truncate(le -% (@as(u64, w.acc) -% le));
                    w.direction = 1;
                } else w.acc = @truncate(@as(u64, w.acc) -% le +% lb);
            }
        } else if (w.acc / RES >= e.samples) w.playing = false;
        return;
    }
    w.acc -%= w.frequency;
    if (looped) {
        const sacc: i32 = @bitCast(w.acc);
        if (@divTrunc(sacc, IRES) < @as(i32, @bitCast(e.loop_begin))) {
            if (e.flags & song.WAVE_PINGPONG != 0) {
                const slb: i32 = @bitCast(@as(u32, @truncate(lb)));
                w.acc = @bitCast(slb -% (sacc -% slb));
                w.direction = 0;
            } else w.acc = @truncate(@as(u64, w.acc) -% lb +% le);
        }
    } else if (@as(i32, @bitCast(w.acc)) < 0) w.playing = false;
}
