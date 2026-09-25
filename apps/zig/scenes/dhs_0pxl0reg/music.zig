// --------------------------------------------------------------------------
// MUSIC. The demo plays YM3 register dumps through its own player ($22954);
// both match library SNDHs at 100 % of the YM registers over every frame, so
// the SNDHs play instead (the YM dump player is deprecated here):
//   "Fake It" by Crazy Q (Crazy_Q/Fake_It.sndh, FLAG ~y): $22A12 at frame 151
//     sets the play flag, the VBL of 152 plays dump frame 0, and dump frame 7
//     is the SNDH's frame 0: it starts at frame 159.
//   $22A1C, the post-music hook from frame 7759, clears the flag after that
//     frame's play: the tune stops there (its volumes are already 0).
//   "AY Tunage" by mOdmate (Modmate/AY_Tuneage.sndh, FLAG ~y): $22A24 loads
//     it at 7868 (after silencing the YM), $22A12 starts it at 8173, after the
//     "end of part one" card; it plays to the end.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const TUNE1 = "dhs_0pxl0reg_fake_it.sndh";
pub const TUNE2 = "dhs_0pxl0reg_ay_tuneage.sndh";
const TUNE1_LAG = 8; // flag set at F, dump frame 7 = SNDH frame 0 plays at F+8

var tunes_started: u32 = 0;
var playing = false;
var song_at: u32 = 0; // frame to request `song` on, 0 = none
var song: []const u8 = TUNE1;

pub fn reset() void {
    tunes_started = 0;
    playing = false;
    song_at = 0;
    song = TUNE1;
}

/// Once a frame: a delayed request falls due.
pub fn tick(frame: u32) void {
    if (song_at != 0 and frame == song_at) {
        zg.requestSong(song);
        song_at = 0;
    }
}

/// $22A12 sets the play flag; setting it again while playing changes nothing.
pub fn on(frame: u32) void {
    if (playing) return;
    playing = true;
    tunes_started += 1;
    song = if (tunes_started == 1) TUNE1 else TUNE2;
    song_at = if (tunes_started == 1) frame + TUNE1_LAG else frame;
}

pub fn off() void {
    if (!playing) return;
    playing = false;
    song_at = 0;
    zg.stopSong();
}
