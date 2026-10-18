// --------------------------------------------------------------------------
// demo-audio.wasm: the FastTracker 2 (.XM) player's exports (libs/zig/players/
// xm.zig). The host stages the file in the song RAM, audioLoadXm checks it
// (refusing with a reason, counted, as audioLoadMod does), audioXmPlay starts
// it. The voices (up to 12) are mixed onto the four Paula channels, so the scope view
// is the MOD's (mode 1).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");

/// XMs refused by the loader, and the last one's reason (xm_format.code).
var xm_rejected: u32 = 0;
var xm_error: u32 = 0;

/// Parse and check the staged XM. Everything else stops first: the file's
/// samples are decoded in the song RAM, where another song's image lives.
export fn audioLoadXm(len: u32) bool {
    m.sfx.songChanged();
    m.mod.stop();
    m.ym.stop();
    m.sap_exports.sap.stop();
    if (m.sndh.active) m.sndh.abandon();
    const p: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    m.xm.load(p[0..len]) catch |e| {
        xm_rejected +%= 1;
        xm_error = players.xm_format.code(e);
        if (m.current_mode == 1) m.current_mode = 0;
        return false;
    };
    xm_error = 0;
    return true;
}
export fn audioXmRejected() u32 {
    return xm_rejected;
}
export fn audioXmError() u32 {
    return xm_error;
}
/// Start the loaded XM at `bpm` (ProTracker's 32..255), or its own tempo when 0.
export fn audioXmPlay(bpm: u32) void {
    m.sfx.songChanged();
    m.ym.stop();
    m.sap_exports.sap.stop();
    m.mod.stop();
    audio.machinePaulaClearScopes();
    m.xm.start(bpm);
    m.current_mode = 1;
}
export fn audioXmStop() void {
    m.xm.stop();
    if (m.current_mode == 1) m.current_mode = 0;
}
