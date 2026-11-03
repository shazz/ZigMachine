// --------------------------------------------------------------------------
// demo-audio.wasm: the klystrack (.kt) player's exports (libs/zig/players/
// kt.zig). The host stages the file in the song RAM, audioLoadKt checks it
// (refusing with a reason, counted, as audioLoadXm does), audioKtPlay starts
// it. cyd's 16-bit stereo plays on the four Paula channels (a high and a low
// byte a side), so the scope view is the MOD's (mode 1).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");

pub var kt: players.KtPlayer = .{};

/// KTs refused by the loader or at start, and the last one's reason (players.kt_read.code;
/// 9 = it loaded but its FX lines do not fit song RAM).
var kt_rejected: u32 = 0;
var kt_error: u32 = 0;

/// Parse and check the staged .kt. Everything else stops first: the song's tables
/// are built in the song RAM, where another song's image lives.
export fn audioLoadKt(len: u32) bool {
    if (m.sndh.active) m.sndh.abandon();
    m.stopAll();
    if (m.current_mode == 1 or m.current_mode == 4) m.current_mode = 0;
    kt.load(len) catch |e| {
        kt_rejected +%= 1;
        kt_error = players.kt_read.code(e);
        return false;
    };
    kt_error = 0;
    return true;
}
export fn audioKtRejected() u32 {
    return kt_rejected;
}
export fn audioKtError() u32 {
    return kt_error;
}
/// Start the loaded song at sequence row `tune` (0: its start). A .kt has one song, so the
/// request's tune field says where to start it, as klystrack's play from the cursor.
export fn audioKtPlay(tune: u32) void {
    m.sfx.songChanged();
    m.stopAll();
    audio.machinePaulaClearScopes();
    if (!kt.start(@intCast(@min(tune, 0xffff)))) {
        kt_rejected +%= 1;
        kt_error = 9;
    }
    m.current_mode = if (kt.active) 1 else 0;
}
export fn audioKtStop() void {
    kt.stop();
    if (m.current_mode == 1) m.current_mode = 0;
}
export fn audioKtActive() bool {
    return kt.active;
}
/// Test only (apps/kt_check.mjs): `n` stereo samples of the core's own output (s16, 22050 Hz),
/// rendered past the chip into the block buffer, whose address this returns (0 when not playing).
export fn audioKtRenderCore(n: u32) u32 {
    if (!kt.active or n > kt.pcm.len / 2) return 0;
    kt.core.render(kt.pcm[0 .. 2 * n]);
    return @intCast(@intFromPtr(kt.pcm.ptr));
}
