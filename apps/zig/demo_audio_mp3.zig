// --------------------------------------------------------------------------
// demo-audio.wasm: the MP3 player's exports (libs/zig/players/mp3.zig). The
// host forwards a cart's zg.mp3Ctl as audioMp3Ctl and its zg.mp3Feed as bytes
// copied to audioMp3FeedPtr then audioMp3Feed(len); zg.mp3Status reads
// audioMp3Status. The PCM plays on the four Paula channels (a high and a low
// byte a side), so the scope view is the MOD's (mode 1).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");

pub var mp3: players.Mp3Player = .{};

export fn audioMp3Ctl(op: u32, arg: u32) void {
    if (op == @intFromEnum(players.mp3.Op.start)) {
        if (m.sndh.active) m.sndh.abandon();
        m.stopAll();
        m.sfx.songChanged();
    }
    mp3.ctl(op, arg);
    if (mp3.active) m.current_mode = 1 else if (m.current_mode == 1) m.current_mode = 0;
}
/// Where the host copies a feed's bytes (at most audioMp3FeedMax), before audioMp3Feed.
export fn audioMp3FeedPtr() u32 {
    return audio.SONG_BASE + players.mp3.STAGE_OFF;
}
export fn audioMp3FeedMax() u32 {
    return players.mp3.STAGE;
}
export fn audioMp3Feed(len: u32) void {
    mp3.feed(len);
}
export fn audioMp3Status(which: u32) u32 {
    return mp3.status(which);
}
/// Bytes the cart fed past a full ring (it overfed: a flow-control bug, harnesses count it).
export fn audioMp3Dropped() u32 {
    return mp3.input.dropped;
}
