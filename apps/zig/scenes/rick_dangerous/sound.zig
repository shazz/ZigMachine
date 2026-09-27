// --------------------------------------------------------------------------
// The sound driver's front end (the model's d_sound.py, literal): play_sound
// $34750 with the drop rule, sound off $34692, the Daglish player's sfx start
// $34F0C, stop $34FAA and tune init $34B98. Only the RAM is transcribed: the
// PSG and Timer A writes are hardware (the Timer A ones drive digi.zig).
//
// What the player HEARS is rick_dangerous.sndh: the same driver's own 68000
// code. Every request the game makes is logged (the harness checks them per
// frame) and, when it is not dropped and not the tick's own tune restart,
// becomes a request for that SNDH's subtune 1 + id + 29 x v (sound.s).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const m = @import("ram.zig");
const F = @import("fields.zig");
const digi = @import("digi.zig");

pub const SOUND_TABLE: i64 = 0x3498A;
const DIGI_RATES: i64 = 0x34A72;
pub const MUS = [3]i64{ 0x34B1A, 0x34B3C, 0x34B5E };
pub const SFX = [3]i64{ 0x34EBE, 0x34ED8, 0x34EF2 };
pub const MIXER: i64 = 0x34EBC;
const SFX_DEFS: i64 = 0x35EA8;
pub const INSTR: i64 = 0x34B7F;
const TUNES: i64 = 0x363B4;
pub const NIDS: i64 = 29;

/// The requests of the current frame: id << 8 | d1, + $10000 dropped, +
/// $20000 sfx_alt, + $40000 the tick's own (make_fixture.py's encoding);
/// OFF for the game's sound off $34692 (not in the fixture: the harness
/// uses it to follow the host requests).
pub var log: [64]u32 = undefined;
pub var log_n: usize = 0;
pub const OFF: u32 = 0xFFFFF;
pub const MUSIC = "rick_dangerous.sndh";
/// The last request the host should play (0 = none), and a sound-off.
pub var subtune: u8 = 0;
pub var stop: bool = false;
/// The VBL tick is running (its tune restart is the SNDH's own business).
pub var in_tick: bool = false;

fn record(n: i64, d1: i64) void {
    const kind = m.rw(SOUND_TABLE + ((n & 0xFF) << 3));
    const dropped = kind != 0 and busy();
    const alt = m.rb(F.SFX_ALT) & 1;
    if (log_n < log.len) {
        log[log_n] = @intCast(((n & 0xFF) << 8) | (d1 & 0xFF) | (@as(i64, @intFromBool(dropped)) << 16) |
            (alt << 17) | (@as(i64, @intFromBool(in_tick)) << 18));
        log_n += 1;
    }
    if (dropped or in_tick) return;
    const v: i64 = if (d1 & 0xFF != 0) 2 else alt;
    subtune = @intCast(1 + (n & 0xFF) + NIDS * v);
    stop = false;
}

/// $34750(d0 = id, d1 = flag).
pub fn play(d0: i64, d1: i64) void {
    record(d0, d1);
    const a0 = SOUND_TABLE + ((d0 & 0xFF) << 3);
    const kind = m.rw(a0);
    if (kind == 1) {
        sfx(a0, d1);
    } else if (kind == 2) {
        digiRequest(a0, d0);
    } else {
        m.wb(F.SND_ID, d0);
        m.wb(F.SND_LOOP, d1);
        musicInit(m.rw(a0 + 2));
        digi.timerA(0, 0); // clr.b $FFFA19
        m.wb(F.SND_MODE, 1);
    }
}

/// A tune playing (1) or a digi busy (bit7) drops every sfx / digi request.
pub fn busy() bool {
    const md = m.rb(F.SND_MODE);
    return md == 1 or md & 0x80 != 0;
}

fn sfx(a0: i64, d1: i64) void {
    if (busy()) return;
    var d6: i64 = 2;
    if (d1 & 0xFF == 0) {
        d6 = m.rb(F.SFX_ALT);
        m.wb(F.SFX_ALT, d6 + 1);
        if (m.rb(F.SFX_ALT) == 2) m.wb(F.SFX_ALT, 0);
    }
    const n = m.rw(a0 + 2);
    const a6 = SFX[0] + d6 * 0x1A;
    const a5 = m.idx(SFX_DEFS, n * 13);
    const d7 = (m.rb(a5 + 0xB) << 8) | m.rb(a5 + 0xA);
    sfxStart(a5, a6, d7, m.rb(a5 + 0xC));
    m.wb(a6 + 0x18, m.rb(a6 + 0x18) | 0x80);
    m.wb(F.MUSIC_BUSY, 0); // clr.b: the high byte of the word
    digi.timerA(0, 0);
    m.wb(F.SND_MODE, 0);
}

fn digiRequest(a0: i64, d0: i64) void {
    if (busy()) return;
    m.wb(F.SND_ID, d0);
    m.wb(F.SND_LOOP, 0);
    const a1 = DIGI_RATES + ((m.rw(a0 + 2) << 1) & 0xFFFF);
    m.wb(F.DIGI_TACR, m.rb(a1));
    m.wb(F.DIGI_TADR, m.rb(a1 + 1));
    m.wl(F.DIGI_NEXT, m.rl(a0 + 4));
    m.wb(F.MUSIC_BUSY, 0);
    m.wb(F.SND_MODE, 2);
}

/// $34692: PSG silent, music_busy / mode / sfx_alt / loop / id = 0, Timer A off.
pub fn off() void {
    m.ww(F.MUSIC_BUSY, 0);
    for ([_]i64{ F.SND_MODE, F.SFX_ALT, F.SND_LOOP, F.SND_ID }) |a| m.wb(a, 0);
    digi.timerA(0, 0);
    if (in_tick) return;
    subtune = 0;
    stop = true;
    if (log_n < log.len) {
        log[log_n] = OFF;
        log_n += 1;
    }
}

/// The host's request for what the game asked since the last flush: the
/// SNDH's subtune, or silence.
pub fn flush() void {
    if (stop) {
        zg.stopSong();
    } else if (subtune != 0) {
        zg.requestSongTune(MUSIC, subtune);
    }
    stop = false;
    subtune = 0;
}

/// $34F0C: fill the sfx channel a6 from the definition a5 (period d7, duration d6).
pub fn sfxStart(a5: i64, a6: i64, d7: i64, d6: i64) void {
    m.wl(a6 + 0x14, a5);
    m.ww(a6 + 4, d7);
    m.ww(a6 + 8, d6);
    m.wb(a6 + 0xA, m.rb(a5 + 5));
    const v = m.rb(a5 + 6) & 0x7F;
    m.wb(a6 + 0xB, (v >> 1) + (v & 1));
    m.wb(a6 + 0xF, m.rb(a5 + 7));
    m.wb(a6 + 0xE, m.rb(a5 + 8));
    m.ww(a6 + 0xC, 0);
    var mix = m.rb(MIXER) | m.rb(a6 + 2);
    const f = m.rb(a5 + 9);
    m.wb(a6 + 0x18, f);
    if (f & 1 != 0) mix &= m.rb(a6);
    if (f & 2 != 0) mix &= m.rb(a6 + 1);
    m.wb(MIXER, mix);
    if (f & 4 == 0) {
        m.wl(a6 + 0x10, 0x350F0);
    } else {
        m.wb(a6 + 6, 0xFF); // (the PSG envelope registers are written directly)
    }
}

/// $34FAA: the mixer shadow |= $3F, the 3 sfx channels' flags cleared.
fn musicStop() void {
    m.wb(MIXER, m.rb(MIXER) | 0x3F);
    for (SFX) |ch| m.wb(ch + 0x18, 0);
}

/// $34B98(d0 = tune): stop, then the 3 music channels from the tune's offsets at $363B4.
fn musicInit(d0: i64) void {
    musicStop();
    var a4 = m.idx(TUNES, (d0 & 0xFF) * 6);
    for (MUS) |ch| {
        m.wl(ch + 2, m.idx(TUNES, m.rw(a4)));
        a4 += 2;
    }
    for (MUS) |ch| {
        m.wb(ch + 0x13, 0);
        m.wb(ch + 0x18, 0);
        for ([_]i64{ 0x14, 0x12, 0x15 }) |off_| m.wb(ch + off_, 1);
        m.wl(ch + 0xE, 0x35E4E);
        m.wb(ch + 0x16, 0xFF);
    }
    var a = INSTR;
    for (0..3) |_| {
        var v: i64 = 0;
        while (v < 0x50) : (v += 10) {
            m.wb(a, v);
            a += 1;
        }
    }
    m.wb(F.MUSIC_BUSY, 0xFF);
}
