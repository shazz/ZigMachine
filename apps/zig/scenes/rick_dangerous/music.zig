// --------------------------------------------------------------------------
// Ben Daglish's player, the tune half (the model's d_music.py, literal): the
// music tick $34C5C and per channel $34CAE -- the arpeggio $34E0E, the
// sequence (patterns, repeats $80-$BF, transpose $FE, instrument table writes
// $C0-$FD, end $FF), the pattern (notes + durations, $7E raw periods, $7F
// rests, effects $34DC4), and the voices started through $34F0C unless an
// sfx owns the voice. Only the RAM is transcribed.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const snd = @import("sound.zig");

const PERIODS: i64 = 0x351A2;
const PATTERNS: i64 = 0x36582;
const PATTERN_BASE: i64 = 0x35FAC;
const INSTR_BASE: i64 = 0x35E4E;
const ARPS: i64 = 0x365E8;

pub fn tick() void {
    if (m.rb(F.MUSIC_BUSY) == 0) return;
    const d0 = m.rb(snd.MUS[0] + 0x16) | m.rb(snd.MUS[1] + 0x16) | m.rb(snd.MUS[2] + 0x16);
    m.wb(F.MUSIC_BUSY, d0);
    if (d0 == 0) {
        if (m.rb(snd.MIXER) & 0x3F != 0x3F) m.wb(F.MUSIC_BUSY, 1);
        return;
    }
    for (snd.MUS, snd.SFX) |a4, a6| channel(a4, a6);
}

/// $34CAE.
fn channel(a4: i64, a6: i64) void {
    arpeggio(a4, a6);
    var a0: i64 = undefined;
    if (m.rb(a4 + 0x14) != 0) {
        a0 = nextPattern(a4) orelse return;
    } else {
        a0 = m.rl(a4 + 0xA);
    }
    m.wb(a4 + 0x15, m.rb(a4 + 0x15) - 1);
    if (m.rb(a4 + 0x15) != 0) return holdNote(a4, a0);
    while (true) { // $34D4E
        if (m.rb(a0) & 0x80 == 0) return note(a4, a6, a0);
        a0 = effect(a4, a0);
        if (m.rb(a4 + 0x14) == 0) continue;
        a0 = nextPattern(a4) orelse return;
        m.wb(a4 + 0x15, m.rb(a4 + 0x15) - 1); // $34D3A again
        if (m.rb(a4 + 0x15) != 0) return holdNote(a4, a0);
    }
}

/// The note still sounding: an effect byte is taken, the pointer stored.
fn holdNote(a4: i64, a0_: i64) void {
    var a0 = a0_;
    if (m.rb(a0) & 0x80 != 0) a0 = effect(a4, a0);
    m.wl(a4 + 0xA, a0);
}

/// $34CBA: the pattern pointer (+$15 not yet decremented), or null when the
/// channel paused or ended.
fn nextPattern(a4: i64) ?i64 {
    m.wb(a4 + 0x12, m.rb(a4 + 0x12) - 1);
    if (m.rb(a4 + 0x12) != 0) {
        m.wl(a4 + 0xA, m.rl(a4 + 6));
        m.wb(a4 + 0x14, 0);
        return m.rl(a4 + 0xA);
    }
    m.wb(a4 + 0x12, 1);
    const a0, const d0 = sequence(a4) orelse return null;
    m.wb(a4 + 0x14, 0);
    m.wl(a4 + 2, a0);
    const pat = m.idx(PATTERN_BASE, m.rw(PATTERNS + 2 * d0));
    m.wl(a4 + 6, pat);
    return pat;
}

/// The sequence's commands up to its next pattern number: the pointer after
/// it and the number, or null at its end ($FF: the channel stops).
fn sequence(a4: i64) ?[2]i64 {
    var a0 = m.rl(a4 + 2);
    while (true) {
        const d0 = m.rb(a0);
        a0 += 1;
        if (d0 & 0x80 == 0) return .{ a0, d0 };
        if (d0 == 0xFE) {
            m.wb(a4 + 0x13, m.rb(a0));
            a0 += 1;
        } else if (d0 == 0xFF) {
            m.wb(a4 + 0x16, 0);
            return null;
        } else if (d0 < 0xC0) {
            m.wb(a4 + 0x12, d0 & 0x1F);
        } else {
            m.wb(m.idx(snd.INSTR, (d0 & 7) + m.rw(a4)), m.rb(a0));
            a0 += 1;
        }
    }
}

/// $34DC4: $80-$88 instrument, $FF end of pattern, $89-$BF flags, $C2
/// nothing, $C0-$FE: 3 bytes skipped. Returns a0.
fn effect(a4: i64, a0_: i64) i64 {
    var a0 = a0_;
    const d0 = m.rb(a0);
    a0 += 1;
    if (m.s8(d0) <= m.s8(0x88)) {
        var w = ((d0 & 7) + m.rw(a4)) & 0xFFFF;
        w = (w & 0xFF00) | m.rb(m.idx(snd.INSTR, w)); // move.b: the low byte only
        m.wl(a4 + 0xE, m.idx(INSTR_BASE, w));
        return a0;
    }
    if (d0 == 0xFF) {
        m.wb(a4 + 0x14, 0xFF);
        return a0;
    }
    if (d0 < 0xC0) {
        m.wb(a4 + 0x18, d0 & 0xF);
        return a0;
    }
    if (d0 == 0xC2) return a0;
    return a0 + 3;
}

/// $34D60: a note (+ transpose + 12) or a $7E raw period, then its duration;
/// starts the voice unless an sfx owns it (bit7 of the voice's +$18).
fn note(a4: i64, a6: i64, a0_: i64) void {
    var a0 = a0_;
    var d0 = m.rb(a0);
    a0 += 1;
    if (d0 == 0x7F) {
        m.wb(a4 + 0x15, m.rb(a0));
        m.wl(a4 + 0xA, a0 + 1);
        return;
    }
    var d7: i64 = undefined;
    if (d0 == 0x7E) {
        d7 = (m.rb(a0 + 1) << 8) | m.rb(a0);
        a0 += 2;
    } else {
        d0 = (d0 + m.rb(a4 + 0x13) + 0xC) & 0xFF;
        m.wb(a4 + 0x17, d0);
        d7 = m.rw(m.idx(PERIODS, 2 * m.s8(d0)));
    }
    m.wb(a4 + 0x20, m.rb(a4 + 0x18) | 0xC0);
    const d6 = m.rb(a0);
    a0 += 1;
    m.wb(a4 + 0x15, d6);
    m.wl(a4 + 0xA, a0);
    if (m.rb(a6 + 0x18) & 0x80 != 0) return;
    snd.sfxStart(m.rl(a4 + 0xE), a6, d7, d6);
}

/// $34E0E: the note's arpeggio ($365E8 + 8 x (+$20 & $1F)).
fn arpeggio(a4: i64, a6: i64) void {
    if (m.rb(a6 + 0x18) & 0x80 != 0) return;
    const c = m.rb(a4 + 0x20);
    if (c & 0x80 == 0) return;
    if (c & 0x3F == 0) {
        m.wb(a4 + 0x20, c & 0x7F);
        return;
    }
    if (c & 0x40 == 0 and arpeggioStep(a4, a6)) return;
    const a0 = ARPS + ((m.rb(a4 + 0x20) << 3) & 0xFF);
    const b = m.rb(a0);
    if (b & 0x80 == 0 and m.rb(a4 + 0x20) & 0x40 == 0) {
        m.wb(a4 + 0x1F, 1);
        return;
    }
    m.wb(a4 + 0x20, m.rb(a4 + 0x20) & ~@as(i64, 0x40));
    m.wb(a4 + 0x1E, (b >> 3) & 7);
    m.wb(a4 + 0x1F, (b & 7) + 1);
    m.wl(a4 + 0x1A, a0 + 1);
    m.ww(a6 + 4, m.rw(m.idx(PERIODS, 2 * m.s8(m.rb(a4 + 0x17)))));
}

/// Within the arpeggio: the delay +$1E, then the next step while its count
/// +$1F lasts. True: done this tick; false: the count ran out (restart it).
fn arpeggioStep(a4: i64, a6: i64) bool {
    m.wb(a4 + 0x1E, m.rb(a4 + 0x1E) - 1);
    if (m.rb(a4 + 0x1E) != 0) return true;
    m.wb(a4 + 0x1F, m.rb(a4 + 0x1F) - 1);
    if (m.rb(a4 + 0x1F) == 0) return false;
    const a0 = m.rl(a4 + 0x1A);
    var d0 = m.rb(a0);
    m.wl(a4 + 0x1A, a0 + 1);
    m.wb(a4 + 0x1E, d0 & 7);
    d0 = (((d0 >> 3) & 0x1F) + m.rb(a4 + 0x17)) & 0xFF;
    m.ww(a6 + 4, m.rw(m.idx(PERIODS, 2 * m.s8(d0))));
    return true;
}
