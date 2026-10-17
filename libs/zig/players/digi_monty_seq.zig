// --------------------------------------------------------------------------
// Monty's sequencer, natively: the song's setup ($EDA), PLAY ($320 -> $814)
// and the row step ($B82) with its commands. The per-frame sound of a voice is
// digi_monty_fx.zig. Offsets: digi_monty_map.zig.
//
//   play   every SPEED frames each voice takes a row; then every frame each
//          voice's period and volume into the YM shadow, and the 13 registers
//          out, 12 down to 0. Once a drum has the channel (DRUMS_ON_C = 1),
//          channel C's period is zeroed and its volume register left to the
//          Timer D handler.
//   rows   a byte < $80 is a note; $80..$93 a command (CMDS); $B8..$BF the
//          speed, $C0..$CF an arpeggio, $D0..$DF an envelope, $E0..$FF a length
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const at = @import("digi_monty_map.zig");
const fx = @import("digi_monty_fx.zig");
const cmd = @import("digi_monty_cmd.zig");
const V = at.V;

const PSG: u32 = 0xFF8800;

/// The song's setup ($EDA), with the YM's ($F60): what the driver's INIT does after Xbtimer.
pub fn start(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    m.wr8(b + at.RUNNING, 0);
    m.wr32(b + at.YM, 0); // registers 0-3
    m.wr16(b + at.YM + 4, 0);
    m.wr32(b + at.YM + 8, 0);
    m.wr8(b + at.MIXER, 0xF8);
    var r: u32 = 13;
    while (r > 0) {
        r -= 1;
        m.wr8(PSG, @intCast(r));
        m.wr8(PSG + 2, m.rd8(b + at.YM + r));
    }
    const song = b + at.MUSIC;
    for (0..4) |i| {
        const v = b + at.VOICES + at.VOICE * @as(u32, @intCast(i));
        m.wr8(v + V.ROW_WAIT, 1);
        m.wr8(v + V.FLAGS, 0);
        m.wr8(v + V.VIB_MODE, 0);
        const track = m.rd32(song + 4 * @as(u32, @intCast(i)));
        m.wr32(v + V.TRACK, track);
        m.wr32(v + V.TRACK_POS, 1);
        const p = @as(u32, m.rd8(track)) << 2;
        m.wr32(v + V.PATTERN, m.rd32(m.rd32(song + 0x14) +% p));
    }
    m.wr8(b + at.TICK, 1);
    m.wr8(b + at.RUNNING, 1);
    m.wr8(b + at.TRANSPOSE, 0);
    m.wr32(b + at.ENVS, m.rd32(song + 0x10));
}

/// PLAY. A voice's period goes through TMP as the 68000 stores it (word, then its high byte back).
pub fn play(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    m.wr8(b + at.PLAY_FLAG, 0xFF);
    if (m.rd8(b + at.RUNNING) != 0) {
        m.wr8(b + at.NOISE_OUT, m.rd8(b + at.NOISE));
        const t = m.rd8(b + at.TICK) -% 1;
        m.wr8(b + at.TICK, t);
        if (t == 0) {
            for (0..4) |i| step(Bus, b, b + at.VOICES + at.VOICE * @as(u32, @intCast(i)));
            m.wr8(b + at.TICK, m.rd8(b + at.SPEED));
        }
        for (0..3) |i| {
            const k: u32 = @intCast(i);
            const out = fx.voice(Bus, b, b + at.VOICES + at.VOICE * k);
            m.wr16(b + at.TMP, out.period);
            m.wr8(b + at.YM + 2 * k, @truncate(out.period));
            m.wr8(b + at.YM + 2 * k + 1, m.rd8(b + at.TMP));
            m.wr8(b + at.YM + 8 + k, out.volume);
        }
        _ = fx.voice(Bus, b, b + at.VOICES + 3 * at.VOICE); // the fourth: noise and mixer only
        m.wr8(b + at.YM + 6, m.rd8(b + at.NOISE_OUT));
    }
    if (m.rd8(b + at.RUNNING) == 0) {
        for (0..11) |i| m.wr8(b + at.YM + @as(u32, @intCast(i)), 0);
        m.wr8(b + at.MIXER, 0x3F);
    }
    writeYm(Bus, b);
}

/// $90E: the port bits of register 7 kept, then 12 down to 0 (10 left out when the drums have C).
fn writeYm(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    m.wr8(PSG, 7);
    const port = m.rd8(PSG) & 0xC0;
    m.wr8(b + at.MIXER, m.rd8(b + at.MIXER) & 0x3F);
    m.wr8(b + at.MIXER, m.rd8(b + at.MIXER) | port);
    if (m.rd8(b + at.DRUMS_ON_C) == 1) {
        m.wr8(b + at.YM + 4, 0);
        m.wr8(b + at.YM + 5, 0);
    }
    var r: u32 = 13;
    while (r > 0) {
        r -= 1;
        if (r == 10 and m.rd8(b + at.DRUMS_ON_C) == 1 and mutant != 3) continue;
        m.wr8(PSG, @intCast(r));
        m.wr8(PSG + 2, m.rd8(b + at.YM + r));
    }
}

/// 3: volume C written over the drums (oracle and harness only: they must catch it).
pub var mutant: u32 = 0;

/// $B82: a voice's row counter; at 0 its next row, else its note bend.
fn step(comptime Bus: type, b: u32, v: u32) void {
    const m = digi.Access(Bus);
    const w = m.rd8(v + V.ROW_WAIT) -% 1;
    m.wr8(v + V.ROW_WAIT, w);
    if (w != 0) return bend(Bus, v);
    m.wr8(v + V.TIE, 0);
    m.wr8(v + V.FLAGS, 0);
    cmd.row(Bus, b, v, m.rd32(v + V.PATTERN));
}

/// $C26: with FLAGS b3, the note bends by BEND a row tick, up with b7.
fn bend(comptime Bus: type, v: u32) void {
    const m = digi.Access(Bus);
    if (!m.btst(v + V.FLAGS, 3)) return;
    const d = m.rd8(v + V.BEND);
    const n = m.rd8(v + V.NOTE);
    m.wr8(v + V.NOTE, if (m.btst(v + V.FLAGS, 7)) n +% d else n -% d);
}
