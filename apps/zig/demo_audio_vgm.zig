// --------------------------------------------------------------------------
// demo-audio.wasm: the .vgm / .vgz player's exports (libs/zig/players/vgm.zig).
// The host stages the file in the song RAM, audioLoadVgm checks and starts it
// (a .vgz is inflated in place; a VGM with neither a YM2612 nor an SN76489 is
// refused, audioVgmStatus says why). The PCM plays on the four Paula channels
// (a high and a low byte a side), so the scope view is the MOD's (mode 1).
// --------------------------------------------------------------------------
const players = @import("players");
const m = @import("root");
const sidlive = @import("demo_audio_sidlive.zig");

pub var vgm: players.VgmPlayer = .{};

/// VGMs refused at load (audioVgmStatus bits 8-15 hold the last one's reason).
var vgm_rejected: u32 = 0;

/// Load the staged .vgm / .vgz and play it from the top, looping where the file says. Everything else
/// stops first: the file is song RAM, where another song's image lives.
export fn audioLoadVgm(len: u32) bool {
    if (bardKeeps()) { // the BARD queue's FM device (or an open with no device yet) plays on over the new tune
        if (!sidlive.vgmPlays()) sidlive.toVgm();
        const ok = vgm.loadUnderLive(len, sidlive.LIVE_OFF);
        if (!ok) vgm_rejected +%= 1;
        return ok;
    }
    if (m.sndh.active) m.sndh.abandon();
    m.stopAll();
    m.sfx.songChanged();
    const ok = vgm.load(len);
    if (!ok) vgm_rejected +%= 1;
    m.current_mode = if (ok) 1 else 0; // stopAll stopped every other player
    return ok;
}
export fn audioVgmStop() void {
    vgm.stop();
    if (m.current_mode == 1) m.current_mode = 0;
}
export fn audioVgmActive() bool {
    return vgm.active and vgm.tune;
}

/// A tune load keeps the BARD queue: it is open and its device is FM or not picked yet.
fn bardKeeps() bool {
    if (!sidlive.open()) return false;
    const d = sidlive.device();
    return d == .fm or d == .none;
}
/// Bit 0 playing; bits 8-15 the last load's answer: 0 ok, 1 not a VGM, 2 no YM2612 / SN76489, 3 truncated,
/// 4 a corrupt or too big .vgz, 5 bigger than the song RAM's room (players.vgm.Load).
export fn audioVgmStatus() u32 {
    return vgm.status();
}
export fn audioVgmRejected() u32 {
    return vgm_rejected;
}
