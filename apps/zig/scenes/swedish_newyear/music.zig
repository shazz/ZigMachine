// The remake's tunes (its LoadAndRun .ym files and two Howl .oggs) as what this
// machine plays; the evidence for each mapping is in swedish_newyear.zig.
const zg = @import("zigos");

pub const Tune = enum { scout, jinx1, icepalace, tcb_intro, tcb_music, dugger1, dugger2, dugger3, dugger4, dugger5 };

/// TCB #2's F1..F5 (KeyCheck: dugger4, dugger5, dugger1, dugger2, dugger3).
pub const dugger_keys = [5]Tune{ .dugger4, .dugger5, .dugger1, .dugger2, .dugger3 };

pub fn play(t: Tune) void {
    switch (t) {
        .scout => zg.requestSongTune("scout.sndh", 1),
        .jinx1 => zg.requestSongTune("Jinks.sndh", 1),
        .icepalace => zg.requestSongTune("beyond_the_ice_palace.sndh", 1),
        .tcb_intro => zg.requestSong("swedish_newyear_tcb_intro.raw"),
        .tcb_music => zg.requestSong("swedish_newyear_tcb_music.raw"),
        .dugger1 => zg.requestSongTune("dugger.sndh", 2),
        .dugger2 => zg.requestSongTune("dugger.sndh", 3),
        .dugger3 => zg.requestSongTune("dugger.sndh", 4),
        .dugger4 => zg.requestSong("swedish_newyear_dugger4.ymraw"),
        .dugger5 => zg.requestSongTune("dugger.sndh", 1),
    }
}
