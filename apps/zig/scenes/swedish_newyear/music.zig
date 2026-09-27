// Every tune of the cart as what this machine plays, each from the disk's own
// replay or mapped by YM register comparison:
//   SYNC #1  Jinks.sndh #1 (Mad Max). The part's replay (TFMX module at $36DF0)
//            wrapped as an SNDH and logged against Jinks #1 over 3000 frames:
//            99.9% of frames identical in periods and volumes at a 2-frame lag.
//   SYNC #2  Swedish_New_Year_Demo_Sync.sndh (Grazey's rip of this very screen's
//            4-voice sample replay, Timer A at 7680 Hz; FLAG ~ay is Timer A, not
//            STE DMA): 90% of its 32-byte windows are found verbatim in the
//            part's code and samples ($2C3FA..$31C00), the rest relocated code.
//   TCB #1   swedish_newyear_tcb_digi.sndh, HAND-BUILT from the disk: TCB #1
//            plays no tune but one sample byte a scanline (~15.65 kHz) through
//            a volume table into YM registers 8-10, the "TCB are the best"
//            speech 10 times then a loop of its stream. The SNDH plays the same
//            stream and table on Timer A at 15754 Hz (the nearest MFP rate);
//            1496 of 1500 frames' volumes are the modelled stream's. No SNDH in
//            the archive holds it (best candidates: none by name or composer).
//   TCB #2   dugger.sndh #4 at the start, #2/#3/#4 on F3/F4/F5 (Mad Max). The
//            part's replay (copied to $50600) wrapped as an SNDH: subtunes 1..4
//            identical to dugger.sndh's, 1.000 aligned at lag 0.
//   OMEGA    beyond_the_ice_palace.sndh #1 (David Whittaker). The part's replay
//            ($8BC4..$9C64, init d0 = 0) wrapped as an SNDH and logged against
//            it over 3000 frames: 1.000 of frames identical at lag 0.
//   menu     scout.sndh #1 (Mad Max, C64-Conversions/Scout)     hist 0.997, seq 0.94
//            (from the remake's .ym dump).
// Every SNDH is FLAG ~y except the Sync one and the TCB digi (~ay, Timer A).
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
