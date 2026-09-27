// Every tune of the cart as what this machine plays; the evidence for each
// mapping is in swedish_newyear.zig.
const zg = @import("zigos");

pub const Tune = union(enum) {
    scout,
    jinx1,
    sync2,
    icepalace,
    tcb_digi,
    dugger: u8, // TCB #2: Dugger subtune 2..4
};

pub fn play(t: Tune) void {
    switch (t) {
        .scout => zg.requestSongTune("scout.sndh", 1),
        .jinx1 => zg.requestSongTune("Jinks.sndh", 1),
        .sync2 => zg.requestSongTune("Swedish_New_Year_Demo_Sync.sndh", 1),
        .icepalace => zg.requestSongTune("beyond_the_ice_palace.sndh", 1),
        .tcb_digi => zg.requestSongTune("swedish_newyear_tcb_digi.sndh", 1),
        .dugger => |n| zg.requestSongTune("dugger.sndh", n),
    }
}
