// --------------------------------------------------------------------------
// KESTREL BOOT: the jingle, on the YM2149 alone (2 MHz: a tone of period P is
// 125000 / P Hz, the envelope's triangle 2e6 / (512 E) Hz). Written for this cart.
//
//   f20 f28 f36  the kestrel's call, "klee-klee-klee": channel C, ~F#6, each note
//                falling in pitch and volume (the third longer)
//   f52..94      the wind of the stoop: noise on channel B, rising in pitch and volume
//   f95          THE CHORD, strummed: A = D2 as the envelope "buzzer" (triangle, E=53,
//                tone off), f96 B = A3 (P 568), f98 C = F#4 (P 338): an open D major
//   f96..259     B and C decay (an exponential table); A leaves the buzzer at f185 for a
//                plain D2 tone (P 1702) that decays out; C wobbles by one period from f130
//   f260-        silence: mixer all off, volumes 0
//
// regsAt(f) is the whole score as a pure function of the frame (the harness models it the
// same way); Player sends the chip only the registers that changed, so R13 (which
// retriggers the envelope on every write) is written exactly once, at the chord.
// No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");
const tl = @import("timeline.zig");

pub const Regs = [14]u8;

const KLEE = [_]u32{ 20, 28, 36 };
const KLEE_VOL = [_]u8{ 14, 13, 11, 9, 7, 5, 3, 2, 1, 1 };
const KLEE_P: u16 = 84; // ~1488 Hz
const WIND: u32 = 52;
const CHORD: u32 = tl.ARRIVE;
const BUZZ_END: u32 = 185;
const ENV_D2: u8 = 53; // 2e6 / (512 * 53) = 73.7 Hz, D2
const P_D2: u16 = 1702;
const P_A3: u16 = 568;
const P_FS4: u16 = 338;

/// The chord's decay: 14 * exp(-t / 50), rounded at compile time.
const DECAY: [tl.SILENT - CHORD]u8 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [tl.SILENT - CHORD]u8 = undefined;
    for (&t, 0..) |*v, i| v.* = @intFromFloat(@round(14.0 * @exp(-@as(f64, @floatFromInt(i)) / 50.0)));
    break :blk t;
};

fn decay(t: u32) u8 {
    return if (t < DECAY.len) DECAY[t] else 0;
}

fn tone(r: *Regs, ch: u2, p: u16, vol: u8) void {
    r[@as(usize, ch) * 2] = @truncate(p);
    r[@as(usize, ch) * 2 + 1] = @truncate(p >> 8);
    r[8 + @as(usize, ch)] = vol;
    r[7] &= ~(@as(u8, 1) << ch);
}

fn call(r: *Regs, f: u32) void {
    for (KLEE, 0..) |k, n| {
        const len: u32 = if (n == 2) KLEE_VOL.len else 7;
        if (f < k or f >= k + len) continue;
        const t = f - k;
        tone(r, 2, KLEE_P + @as(u16, @intCast(t)) * @as(u16, if (n == 2) 3 else 2), KLEE_VOL[t]);
    }
}

fn wind(r: *Regs, f: u32) void {
    if (f < WIND or f >= CHORD) return;
    const t = f - WIND;
    r[6] = @intCast(30 - t * 24 / (CHORD - WIND));
    r[9] = @intCast(t * 10 / (CHORD - WIND));
    r[7] &= ~@as(u8, 1 << 4); // noise on B
}

fn chord(r: *Regs, f: u32) void {
    r[11] = ENV_D2; // the envelope stays set up after the chord: R13 is not written again
    r[13] = 0x0E;
    if (f < BUZZ_END) {
        r[8] = 0x10; // A follows the envelope, tone and noise off: the buzzer
    } else {
        tone(r, 0, P_D2, @intCast(9 - @min(9, (f - BUZZ_END) * 9 / (tl.SILENT - 5 - BUZZ_END))));
    }
    if (f >= CHORD + 1) tone(r, 1, P_A3, decay(f - CHORD - 1));
    const wobble: u16 = if (f >= 130 and (f / 6) % 2 == 1) 1 else 0;
    if (f >= CHORD + 3) tone(r, 2, P_FS4 + wobble, decay(f - CHORD - 3) -| 1);
}

/// The YM registers at frame `f` (R13 is 0 before the chord: never sent, see Player).
pub fn regsAt(f: u32) Regs {
    var r: Regs = [_]u8{0} ** 14;
    r[7] = 0x3F;
    if (f >= tl.SILENT) { // silent, the envelope left as the chord set it (no R13 write)
        r[11] = ENV_D2;
        r[13] = 0x0E;
        return r;
    }
    call(&r, f);
    wind(&r, f);
    if (f >= CHORD) chord(&r, f);
    return r;
}

/// Sends a frame's registers to the chip through `write` (zg.ymWrite in the cart): every
/// register but R13 on the first frame, then only the ones that changed.
pub const Player = struct {
    sent: Regs = [_]u8{0} ** 14,
    started: bool = false,
    refused: u32 = 0,

    pub fn tick(self: *Player, f: u32, write: *const fn (u8, u8) bool) void {
        const r = regsAt(f);
        for (r, 0..) |v, i| {
            const first = !self.started and i != 13;
            if (!first and v == self.sent[i]) continue;
            if (!write(@intCast(i), v)) self.refused +%= 1;
            self.sent[i] = v;
        }
        self.started = true;
    }
};

var test_writes: u32 = 0;
var test_r13: u32 = 0;
fn testWrite(reg: u8, _: u8) bool {
    test_writes += 1;
    if (reg == 13) test_r13 += 1;
    return true;
}

test "the score: R13 once, silent at the end, writes bounded" {
    var p: Player = .{};
    var f: u32 = 0;
    while (f < 400) : (f += 1) p.tick(f, testWrite);
    try std.testing.expectEqual(@as(u32, 1), test_r13);
    try std.testing.expect(test_writes < 600);
    const end = regsAt(tl.SILENT);
    try std.testing.expectEqual(@as(u8, 0x3F), end[7]);
    try std.testing.expectEqual(@as(u8, 0), end[8] | end[9] | end[10]);
    try std.testing.expectEqual(@as(u8, 0x10), regsAt(CHORD)[8]);
}
