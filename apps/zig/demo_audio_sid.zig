// --------------------------------------------------------------------------
// demo-audio.wasm: the .sid player's exports (libs/zig/players/sid.zig). The
// host stages the file in the song RAM, audioLoadSid checks and starts it
// (PSID only: an RSID is refused, audioSidStatus says why). The PCM plays on
// the four Paula channels (a high and a low byte a side), so the scope view is
// the MOD's (mode 1).
// --------------------------------------------------------------------------
const players = @import("players");
const m = @import("root");

pub var sid: players.SidPlayer = .{};

/// SIDs refused at load (audioSidStatus bits 8-15 hold the last one's reason).
var sid_rejected: u32 = 0;

/// Load the staged .sid and play subtune `tune` (1-based, 0 = its default). Everything else stops
/// first: the file is song RAM, where another song's image lives.
export fn audioLoadSid(len: u32, tune: u32) bool {
    if (m.sndh.active) m.sndh.abandon();
    m.stopAll();
    m.sfx.songChanged();
    const ok = sid.load(len, tune);
    if (!ok) sid_rejected +%= 1;
    m.current_mode = if (ok) 1 else 0; // stopAll stopped every other player
    return ok;
}
export fn audioSidStop() void {
    sid.stop();
    if (m.current_mode == 1) m.current_mode = 0;
}
export fn audioSidActive() bool {
    return sid.active;
}
/// Bit 0 playing; bits 8-15 the last load's answer: 0 ok, 1 not a .sid, 2 RSID (not supported),
/// 3 a bad length (players.sid.Load).
export fn audioSidStatus() u32 {
    return sid.status();
}
export fn audioSidRejected() u32 {
    return sid_rejected;
}
