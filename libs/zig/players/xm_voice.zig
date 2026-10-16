// --------------------------------------------------------------------------
// One XM channel's state beyond its mixer voice (xm_mix.zig): the note and
// its pitch, the volume, the portamento and vibrato, and the instrument's
// volume envelope with its fadeout. Once a tick the gain is worked out from
// these (gainOf), and the mixer reads it. Pure: no chip. Tested natively
// (xm_mix_test.zig).
// --------------------------------------------------------------------------
const xmix = @import("xm_mix.zig");
const inst = @import("xm_instr.zig");

pub const Chan = struct {
    mix: xmix.Voice = .{},
    inst: u8 = 0, // 1-based instrument, 0 = none yet
    vol: u8 = 0, // 0..64
    semi: i32 = 0, // the note's semitone from C-0, relnote added
    ft: i32 = 0, // the sample's finetune
    base_period: i32 = 0, // the note's period, before any slide or vibrato
    period: i32 = 0, // after slides and arpeggio, before vibrato
    target: i32 = 0, // tone portamento's target period
    vib_pos: u32 = 0,
    /// The last non-zero parameter of each memoised effect (see effects.zig).
    memo: [16]u8 = undefined, // zeroed by XmPlayer.start (a zero default would be data-segment bytes)
    pending: u8 = 0, // EDx: the note a note delay will start (0 = none)
    eff: u8 = 0, // the current row's effect
    param: u8 = 0,
    env_tick: u32 = 0, // ticks since the note: the envelope's position
    key_on: bool = false,
    fade: u32 = 65536, // Q16: 65536 while the key is down, falling after key-off
};

/// The envelope's value at `tick` (0..64). A sustain point holds while the key is
/// down; a loop wraps the envelope between its two points; past the last point
/// the value stays put (the fadeout takes the voice down from there).
pub fn envValue(e: *const inst.Envelope, tick: u32, key_on: bool) u32 {
    if (!e.on or e.n == 0) return 64;
    const n: usize = e.n;
    var t = tick;
    if (e.sustain_on and key_on and e.sustain < n) {
        const sx: u32 = e.pts[e.sustain].x;
        if (t >= sx) return clampEnv(e.pts[e.sustain].y);
    }
    if (e.loop_on and e.loop_start < n and e.loop_end < n) {
        const xs: u32 = e.pts[e.loop_start].x;
        const xe: u32 = e.pts[e.loop_end].x;
        if (xe > xs and t >= xe) t = xs + (t - xs) % (xe - xs);
    }
    return segment(e, n, t);
}

/// Interpolate between the two points around `t`.
fn segment(e: *const inst.Envelope, n: usize, t: u32) u32 {
    var k: usize = 0;
    while (k + 1 < n and e.pts[k + 1].x <= t) k += 1;
    if (k + 1 >= n) return clampEnv(e.pts[n - 1].y);
    const a = e.pts[k];
    const b = e.pts[k + 1];
    if (b.x <= a.x or t <= a.x) return clampEnv(a.y);
    const dx: u32 = b.x - a.x;
    const dy: i32 = @as(i32, b.y) - @as(i32, a.y);
    const y: i32 = @as(i32, a.y) + @divTrunc(dy * @as(i32, @intCast(t - a.x)), @as(i32, @intCast(dx)));
    return clampEnv(@intCast(@max(y, 0)));
}

fn clampEnv(y: u16) u32 {
    return @min(@as(u32, y), 64);
}

/// The channel's gain for this tick: volume x envelope x fadeout (0..64).
pub fn gainOf(c: *const Chan, e: *const inst.Envelope) u32 {
    return xmix.voiceGain(c.vol, envValue(e, c.env_tick, c.key_on), c.fade);
}

/// Advance the envelope and the fadeout by one tick. The fadeout only falls
/// once the key is up.
pub fn tickEnvelope(c: *Chan, fadeout: u16) void {
    c.env_tick +|= 1;
    if (!c.key_on) c.fade -|= fadeout;
}

/// Start a note: the envelope and fadeout restart with it, the key goes down.
pub fn keyOn(c: *Chan) void {
    c.key_on = true;
    c.env_tick = 0;
    c.fade = 65536;
}
