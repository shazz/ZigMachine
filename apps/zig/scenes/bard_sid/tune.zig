// --------------------------------------------------------------------------
// BARD SID's tune: a tiny three-voice tracker written as a C64 player writes
// the SID, one 50 Hz tick at a time (what a GoatTracker replay will do through
// the same queue). 64 rows of 6 ticks, Am F C G:
//   voice 1  a pulse bass, its pulse width swept, through the low-pass filter
//            whose cutoff breathes on a sine table
//   voice 2  a sawtooth arpeggio over the chord, a note a tick
//   voice 3  drums: a kick (triangle, its pitch dropping), a snare and a hat (noise)
// Only what changes is written, as a real replay would. tick(k) depends on k alone.
// --------------------------------------------------------------------------
const std = @import("std");

pub const TICKS_PER_ROW: u32 = 6;
pub const ROWS: u32 = 64;
pub const MAX_WRITES: u32 = 24;

pub const Write = struct { reg: u8, val: u8 };
pub const Tick = struct {
    w: [MAX_WRITES]Write = undefined,
    n: u32 = 0,
    beat: bool = false, // a beat starts on this tick (rows 0, 4, 8...)
    row: u32 = 0,

    fn put(self: *Tick, reg: u8, val: u8) void {
        self.w[self.n] = .{ .reg = reg, .val = val };
        self.n += 1;
    }
    fn freq(self: *Tick, voice: u8, note: u8) void {
        const f = FREQ[note];
        self.put(voice * 7, @truncate(f));
        self.put(voice * 7 + 1, @truncate(f >> 8));
    }
};

/// The SID's frequency register a MIDI note (PAL clock 985,248 Hz): f * 2^24 / clock. Built at
/// compile time (float only here, never per frame).
const FREQ: [128]u16 = blk: {
    @setEvalBranchQuota(20000);
    var t: [128]u16 = undefined;
    for (&t, 0..) |*e, m| {
        const f = 440.0 * std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(m)) - 69.0) / 12.0);
        e.* = @intFromFloat(@min(65535.0, @round(f * 16777216.0 / 985248.0)));
    }
    break :blk t;
};

/// The four chords' roots and thirds (MIDI): Am, F, C, G, sixteen rows each.
const ROOT = [4]u8{ 33, 29, 36, 31 };
const THIRD = [4]u8{ 3, 4, 4, 4 };
/// The cutoff's breath: a 64-step sine, 0..255.
const SINE: [64]u8 = blk: {
    var t: [64]u8 = undefined;
    for (&t, 0..) |*e, i| e.* = @intFromFloat(@round(127.5 + 127.5 * @sin(@as(f64, @floatFromInt(i)) * std.math.pi / 32.0)));
    break :blk t;
};
const BASS_STEPS = [8]u8{ 0, 12, 0, 0, 7, 0, 12, 10 };

/// The registers the tune sets once, after the SID's reset (tick 0).
fn setup(t: *Tick) void {
    t.put(0x05, 0x09); // bass AD
    t.put(0x06, 0x80); // bass SR
    t.put(0x0C, 0x28); // lead AD
    t.put(0x0D, 0x96); // lead SR
    t.put(0x13, 0x08); // drums AD
    t.put(0x14, 0x00); // drums SR
    t.put(0x17, 0x71); // resonance 7, filter voice 1
    t.put(0x18, 0x1F); // low pass, volume 15
}

/// Tick k's writes; `reset`: the SID was just reset (tick 0, or a new model), so the setup first.
pub fn tick(k: u32, reset: bool) Tick {
    var t: Tick = .{};
    const row = (k / TICKS_PER_ROW) % ROWS;
    const sub = k % TICKS_PER_ROW;
    t.row = row;
    if (reset) setup(&t);
    const chord = row / 16;
    // Bass: a note a row from the step pattern, gated short; pulse width swept every tick.
    if (sub == 0) {
        t.freq(0, ROOT[chord] + BASS_STEPS[row % 8]);
        t.put(0x04, 0x41);
    } else if (sub == 3) t.put(0x04, 0x40);
    const pw: u16 = 0x200 + @as(u16, SINE[(k / 2) % 64]) * 6;
    t.put(0x02, @truncate(pw));
    t.put(0x03, @truncate(pw >> 8));
    t.put(0x16, 0x10 + SINE[(k / 3) % 64] / 3); // the cutoff's high byte
    // Lead: the chord a note a tick, two octaves up, gated for three rows of four.
    const arp = [3]u8{ 0, THIRD[chord], 7 };
    t.freq(1, ROOT[chord] + 36 + arp[k % 3]);
    if (row % 4 == 0 and sub == 0) t.put(0x0B, 0x21) else if (row % 4 == 3 and sub == 0) t.put(0x0B, 0x20);
    drums(&t, row, sub);
    t.beat = row % 4 == 0 and sub == 0;
    return t;
}

fn drums(t: *Tick, row: u32, sub: u32) void {
    const step = row % 8;
    if (step == 0 or step == 6) { // kick: triangle, the pitch falling over three ticks
        const kick = [3]u8{ 0x0C, 0x06, 0x03 };
        if (sub < 3) t.put(0x0F, kick[sub]);
        if (sub == 0) t.put(0x12, 0x11) else if (sub == 3) t.put(0x12, 0x10);
    } else if (step == 4) { // snare: noise
        if (sub == 0) {
            t.put(0x0F, 0x24);
            t.put(0x12, 0x81);
        } else if (sub == 2) t.put(0x12, 0x80);
    } else if (step % 2 == 1 and sub == 0) { // hat: high noise, one tick
        t.put(0x0F, 0x70);
        t.put(0x12, 0x81);
    } else if (step % 2 == 1 and sub == 1) t.put(0x12, 0x80);
}

test "a tick depends on its number alone and fits its writes" {
    var k: u32 = 0;
    while (k < TICKS_PER_ROW * ROWS * 2) : (k += 1) {
        const a = tick(k, k == 0);
        const b = tick(k, k == 0);
        try std.testing.expect(a.n <= MAX_WRITES);
        try std.testing.expectEqualSlices(Write, a.w[0..a.n], b.w[0..b.n]);
    }
    try std.testing.expect(tick(0, true).beat and !tick(1, false).beat and tick(4 * TICKS_PER_ROW, false).beat);
    try std.testing.expectEqual(@as(u16, 0x1D45), FREQ[69]); // A4: 440 * 2^24 / 985248 = 7493
}
