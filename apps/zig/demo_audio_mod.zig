// --------------------------------------------------------------------------
// demo-audio.wasm: the MOD player's exports (its level: zg.requestModVolume),
// and the sound effects a game plays OVER a MOD (zg.sfxPlay / sfxStop /
// ymWrite, libs/zig/sfx_queue.zig;
// the voice: libs/zig/players/sfx_voice.zig). Split from demo_audio_main.zig,
// whose players and mode they share.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const sfx_voice = players.sfx_voice;
const m = @import("root");

/// MODs refused by the loader, and the last one's reason (mod_format.code).
var mod_rejected: u32 = 0;
var mod_error: u32 = 0;

// --- MOD player ---
/// False for anything but a 4-channel ProTracker MOD (M.K., M!K!, 4CHN,
/// FLT4): a 6CHN / 8CHN file read as four channels plays garbage. Counted
/// (audioModRejected), with the reason (audioModError), so the host says so.
export fn audioLoadMod(len: u32) bool {
    m.sfx.songChanged();
    // An SNDH playing would go on rendering over the MOD (it comes first in
    // audioRender), and its image was just overwritten by this file.
    if (m.sndh.active) {
        m.sndh.abandon();
        m.sfx.reset();
        if (m.current_mode == 4) m.current_mode = 0;
    }
    m.mod.load(m.songSlice(len)) catch |e| {
        mod_rejected +%= 1;
        mod_error = players.mod_format.code(e);
        if (m.current_mode == 1) m.current_mode = 0;
        return false;
    };
    mod_error = 0;
    return true;
}
export fn audioModRejected() u32 {
    return mod_rejected;
}
export fn audioModError() u32 {
    return mod_error;
}
export fn audioModPlay() void {
    m.sfx.songChanged();
    m.ym.stop();
    audio.machinePaulaClearScopes();
    m.mod.start();
    m.current_mode = 1;
}
/// Play at a start tempo (zg.requestModBpm). ProTracker tempos are 32..255
/// (below $20 an Fxx is a speed); anything else is not a tempo, and plays at
/// ProTracker's 125 exactly as audioModPlay does, the way tune 0 does.
export fn audioModPlayBpm(bpm: u32) void {
    if (bpm < 32 or bpm > 255) return audioModPlay();
    m.sfx.songChanged();
    m.ym.stop();
    audio.machinePaulaClearScopes();
    m.mod.startAtBpm(@intCast(bpm));
    m.current_mode = 1;
}
/// zg.requestModVolume: the MOD's own channels at q16 / 65536 (0..65536) of
/// their volume, the effect's lent channel untouched (ModPlayer.setGain).
/// False, and counted in audioSfxRefused, when no MOD plays or q16 > 1.0.
export fn audioModGain(q16: u32) bool {
    const ok = m.current_mode == 1 and m.mod.active and q16 <= 65536 and
        m.mod.setGain(@as(f32, @floatFromInt(q16)) / 65536.0);
    if (!ok) m.sfx.refused +%= 1;
    return ok;
}
export fn audioModStop() void {
    m.sfx.songChanged();
    m.mod.stop();
    if (m.current_mode == 1) m.current_mode = 0;
}

// --- sound effects over a MOD (zg.sfxPlay / sfxStop / ymWrite; sfx_voice.zig) ---
/// Where the host writes an effect's signed 8-bit PCM (the top of song RAM),
/// and how much fits. 0 while no effect can play: no MOD, or one reaching
/// into the buffer; an SNDH's 68000 RAM is there, so nothing may be written.
export fn audioSfxBufPtr() usize {
    if (!m.mod.active or m.mod.data.len > sfx_voice.BUF_OFFSET) return 0;
    return @intFromPtr(sfx_voice.buf());
}
export fn audioSfxBufCapacity() u32 {
    return sfx_voice.CAP;
}
/// Play the first `len` bytes of the buffer at `rate` Hz on the MOD's quiet
/// channel. False (and counted) when no MOD is playing or len / rate is bad.
export fn audioSfxPlay(len: u32, rate: u32, loop: u32) bool {
    return m.sfx.play(&m.mod, len, rate, loop != 0);
}
/// Stop the effect; `loop_only`: only a looped one.
export fn audioSfxStop(loop_only: u32) void {
    m.sfx.stop(&m.mod, loop_only != 0);
}
/// A YM register under the MOD. Refused (false, counted) while an SNDH or a
/// YM dump drives the chip.
export fn audioSfxYm(reg: u32, val: u32) bool {
    return m.sfx.ym(reg, val, m.sndh.active or m.ym.active);
}
/// The Paula channel the effect holds, or -1.
export fn audioSfxChannel() i32 {
    return if (m.sfx.ch) |c| c else -1;
}
export fn audioSfxPlays() u32 {
    return m.sfx.plays;
}
export fn audioSfxRefused() u32 {
    return m.sfx.refused;
}
