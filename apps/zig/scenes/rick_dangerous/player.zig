// --------------------------------------------------------------------------
// The VBL sound tick $3488E and the voices of Ben Daglish's player (the
// model's d_player.py, literal; the tune half is music.zig). Only the RAM is
// transcribed: the PSG writes are hardware.
//
//   tick   digi busy: nothing; the voice envelopes $34FF0; then by snd_mode:
//          0 done, 1 a tune (music tick $34C5C, or at its end silence, or the
//          tune again when snd_loop), 2 a digi pending: mode $FF, digi_ptr =
//          digi_next, Timer A on
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const snd = @import("sound.zig");
const music = @import("music.zig");
const digi = @import("digi.zig");

/// $3488E.
pub fn tick() void {
    snd.in_tick = true;
    defer snd.in_tick = false;
    if (m.rb(F.SND_MODE) & 0x80 != 0) return;
    voices();
    const md = m.rb(F.SND_MODE);
    if (md == 0) return;
    if (md != 1) {
        m.wb(F.SND_MODE, 0xFF); // $348EA: PSG off, Timer A on
        m.wl(F.DIGI_PTR, m.rl(F.DIGI_NEXT));
        digi.timerA(m.rb(F.DIGI_TACR), m.rb(F.DIGI_TADR));
        return;
    }
    if (m.rw(F.MUSIC_BUSY) == 0) {
        if (m.rb(F.SND_LOOP) == 0) {
            snd.off();
            return;
        }
        snd.play(m.rb(F.SND_ID), 1);
    }
    music.tick();
}

/// $34FF0: the three voices.
fn voices() void {
    for (snd.SFX) |a6| voice(a6);
}

/// $350B8.
fn voice(a6: i64) void {
    if (m.rb(snd.MIXER) & m.rb(a6 + 2) == m.rb(a6 + 2)) return;
    const a5 = m.rl(a6 + 0x14);
    const w = m.rw(a6 + 8);
    if (w != 0 and w != 0xFFFF) m.ww(a6 + 8, w - 1);
    sweep(a6, a5);
    if (m.rb(a6 + 0x18) & 4 != 0) {
        if (m.rw(a6 + 8) != 0) return;
        return releaseEnd(a6);
    }
    switch (m.rl(a6 + 0x10)) {
        0x350F0 => attack(a6, a5),
        0x35112 => decay(a6, a5),
        0x35136 => sustain(a6),
        0x35146 => release(a6, a5),
        else => {}, // $35110: an rts; the model raises on any other routine (never met)
    }
}

/// $3516A: after a delay (+$A, $FF = stopped), +$C += +$E every step, +$B
/// steps, then the direction flips (a5+6 > 0) or it stops (a5+6 < 0).
fn sweep(a6: i64, a5: i64) void {
    var d0 = m.rb(a6 + 0xA);
    if (d0 != 0) {
        if (d0 == 0xFF) return;
        m.wb(a6 + 0xA, d0 - 1);
        if (d0 - 1 != 0) return;
    }
    m.ww(a6 + 0xC, m.rw(a6 + 0xC) + m.rw(a6 + 0xE));
    m.wb(a6 + 0xB, m.rb(a6 + 0xB) - 1);
    if (m.rb(a6 + 0xB) != 0) return;
    d0 = m.rb(a5 + 6);
    if (d0 == 0) return;
    if (d0 & 0x80 != 0) {
        m.wb(a6 + 0xA, 0xFF);
        return;
    }
    m.wb(a6 + 0xB, d0);
    m.ww(a6 + 0xE, -m.rw(a6 + 0xE));
}

fn addVol(a6: i64, v: i64) i64 {
    const r = (m.rb(a6 + 6) + v) & 0xFF;
    m.wb(a6 + 6, r);
    return r;
}

/// $350F0: volume += a5[0] up to a5[4], then decay.
fn attack(a6: i64, a5: i64) void {
    const r = addVol(a6, m.rb(a5));
    if (r & 0x80 == 0 and m.s8(m.rb(a5 + 4)) > m.s8(r)) return;
    m.wb(a6 + 6, m.rb(a5 + 4));
    m.wl(a6 + 0x10, 0x35112);
}

/// $35112: volume += a5[1] down to a5[2], then sustain.
fn decay(a6: i64, a5: i64) void {
    const r = addVol(a6, m.rb(a5 + 1));
    if (r & 0x80 == 0 and m.s8(m.rb(a5 + 2)) < m.s8(r)) return;
    m.wb(a6 + 6, m.rb(a5 + 2));
    m.wl(a6 + 0x10, 0x35136);
}

/// $35136: until the duration +8 runs out, then release.
fn sustain(a6: i64) void {
    if (m.rw(a6 + 8) != 0) return;
    m.wl(a6 + 0x10, 0x35146);
}

/// $35146: volume += a5[3] until it goes negative, then the voice is off.
fn release(a6: i64, a5: i64) void {
    if (addVol(a6, m.rb(a5 + 3)) & 0x80 == 0) return;
    releaseEnd(a6);
}

/// $35150: volume 0, its mixer bits set (off), bit7 of +$18 cleared.
fn releaseEnd(a6: i64) void {
    m.wb(a6 + 6, 0);
    m.wb(snd.MIXER, m.rb(snd.MIXER) | m.rb(a6 + 2));
    m.wb(a6 + 0x18, m.rb(a6 + 0x18) & 0x7F);
}
