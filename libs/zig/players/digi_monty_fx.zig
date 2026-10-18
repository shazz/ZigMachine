// --------------------------------------------------------------------------
// Monty's per-frame voice ($CE6): a voice's volume envelope, arpeggio, period,
// vibrato, slide, noise sweep, mixer bits and volume decay, every access the
// 68000's, in its order. Returns what play stores in the YM shadow: the
// period (its d0.w) and the volume (its d1.b).
//
// Byte arithmetic is the 68000's: `subq.b #1; bcc` is "it was not 0", and
// only the low byte of d0 picks the period, whatever its high byte held.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const at = @import("digi_monty_map.zig");
const V = at.V;

/// The 68000's d7 after the last voice: its byte goes into trigger's movem
/// save (digi_monty_cmd.zig). Above that, 0: no output depends on it.
pub var d7: u32 = 0;

pub const Out = struct { period: u16, volume: u8 };

pub fn voice(comptime Bus: type, b: u32, v: u32) Out {
    const m = digi.Access(Bus);
    const flags = m.rd8(v + V.FLAGS);
    if (flags & 0x20 != 0) envelope(Bus, v);
    var n = m.rd8(v + V.NOTE) +% m.rd8(b + at.TRANSPOSE);
    if (countDown(Bus, v + V.ARP_WAIT)) n +%= arpeggio(Bus, v);
    n +%= @truncate(m.rd16(v + V.SHIFT));
    const idx: u8 = n +% n;
    var period = m.rd16(b + at.PERIODS + idx);
    const mode = m.rd8(v + V.VIB_MODE);
    if (mode & 0x40 != 0 and vibratoDue(Bus, v)) period +%= vibrato(Bus, v, mode, flags, idx);
    const now = flags ^ 1;
    m.wr8(v + V.FLAGS, now);
    if (now & 4 != 0) period +%= slide(Bus, v);
    var mix = m.rd8(b + at.MIX_MASK);
    if (~now & 3 == 0) {
        m.wr8(b + at.NOISE_OUT, m.rd8(b + at.NOISE) ^ 8);
        mix = 7;
    }
    d7 = ~now & 3;
    if (m.btst(v + V.EFX, 1)) sweep(Bus, b, v);
    const old = m.rd8(b + at.MIXER);
    m.wr8(b + at.MIXER, ((mix ^ old) & m.rd8(v + V.MIX)) ^ old);
    if (m.btst(v + V.EFX, 2) and countDown(Bus, v + V.DECAY_WAIT)) decay(Bus, v);
    return .{ .period = period, .volume = m.rd8(v + V.VOLUME) };
}

/// `subq.b #1,(a); bcc`: true when the byte was 0 (it wraps to $FF: time to reload).
fn countDown(comptime Bus: type, a: u32) bool {
    const m = digi.Access(Bus);
    const w = m.rd8(a);
    m.wr8(a, w -% 1);
    return w == 0;
}

fn envelope(comptime Bus: type, v: u32) void {
    const m = digi.Access(Bus);
    if (countDown(Bus, v + V.ENV_WAIT)) {
        m.wr8(v + V.ENV_WAIT, m.rd8(v + V.ENV_SPEED));
        const e = m.rd32(v + V.ENV_POS);
        if (m.rd8(e +% 1) != 0xFF) {
            m.wr32(v + V.ENV_POS, m.rd32(v + V.ENV_POS) +% 1);
            m.wr8(v + V.ENV_LEVEL, m.rd8(e +% 1));
        }
    }
    m.wr8(v + V.VOLUME, m.rd8(v + V.ENV_LEVEL));
}

/// Only on the frame the arpeggio's counter reloads: $FF restarts it, $FE holds the last step.
fn arpeggio(comptime Bus: type, v: u32) u8 {
    const m = digi.Access(Bus);
    m.wr8(v + V.ARP_WAIT, m.rd8(v + V.ARP_SPEED));
    var a = m.rd32(v + V.ARP);
    var s = m.rd8(a);
    if (s == 0xFF) {
        a = m.rd32(v + V.ARP_START);
        s = m.rd8(a);
    }
    if (s == 0xFE) {
        a -%= 1;
        s = m.rd8(a);
    }
    m.wr32(v + V.ARP, a +% 1);
    return s;
}

fn vibratoDue(comptime Bus: type, v: u32) bool {
    const m = digi.Access(Bus);
    if (m.rd8(v + V.VIB_GO) != 1 and !countDown(Bus, v + V.VIB_WAIT)) return false;
    m.wr8(v + V.VIB_GO, 1);
    return true;
}

/// $D9E: a triangle between 0 and 2 * depth, centred, scaled up an octave at a
/// time below the period table's index $60 (the add of $A0, then $18 a shift).
fn vibrato(comptime Bus: type, v: u32, mode: u8, flags: u8, idx: u8) u16 {
    const m = digi.Access(Bus);
    var top = m.rd8(v + V.VIB_DEPTH) << 1;
    var pos = m.rd8(v + V.VIB_POS);
    if (!(mode & 0x80 != 0 and flags & 1 != 0)) {
        const s = m.rd8(v + V.VIB_STEP);
        if (mode & 0x20 == 0) {
            if (pos < s) {
                m.bset(v + V.VIB_MODE, 5);
                pos = 0;
            } else pos -= s;
        } else {
            pos +%= s;
            if (pos >= top) {
                m.bclr(v + V.VIB_MODE, 5);
                pos = top;
            }
        }
        m.wr8(v + V.VIB_POS, pos);
    }
    top >>= 1;
    var d: u16 = if (pos < top) 0xFF00 | @as(u16, pos -% top) else pos - top;
    var o, var carry = @addWithOverflow(idx, 0xA0);
    while (carry == 0) {
        d <<= 1;
        o, carry = @addWithOverflow(o, 0x18);
    }
    return d;
}

/// $E1C: after SLIDE_WAIT frames, SLIDE grows by the signed SLIDE_STEP every frame.
fn slide(comptime Bus: type, v: u32) u16 {
    const m = digi.Access(Bus);
    const w = m.rd8(v + V.SLIDE_WAIT) -% 1;
    if (w != 0) {
        m.wr8(v + V.SLIDE_WAIT, w);
        return 0;
    }
    const step: u16 = @bitCast(@as(i16, @as(i8, @bitCast(m.rd8(v + V.SLIDE_STEP)))));
    const s = step +% m.rd16(v + V.SLIDE);
    m.wr16(v + V.SLIDE, s);
    return s;
}

/// $E78: the noise period climbs by 2 a frame from SWEEP, until it reaches $40 (signed compare).
fn sweep(comptime Bus: type, b: u32, v: u32) void {
    const m = digi.Access(Bus);
    const s = m.rd8(v + V.SWEEP) +% 2;
    m.wr8(v + V.SWEEP, s);
    if ((s -% 0x40) & 0x80 == 0) m.bclr(v + V.EFX, 1);
    m.wr8(b + at.NOISE, m.rd8(v + V.SWEEP));
}

fn decay(comptime Bus: type, v: u32) void {
    const m = digi.Access(Bus);
    m.wr8(v + V.DECAY_WAIT, m.rd8(v + V.DECAY_SPEED));
    m.wr8(v + V.VOLUME, m.rd8(v + V.VOLUME) -% 1);
    if (m.rd8(v + V.VOLUME) == 0) m.bclr(v + V.EFX, 2);
}
