// --------------------------------------------------------------------------
// Union cracktro playlist: keys 1-6 (union_intro.zig, main.zig). The scene OWNS
// it (the host holds none): files under docs/music/union/.
//
// The originals are the remake's prototypes/oldies/UnionDemoCracktro/intro/zik/
// *.ym (LHA'd YM5/YM6). Proof, 2026-10-20, each SNDH rendered headless through
// the real demo-audio + machine-audio modules against that YM: "periods" = the
// tone periods of every channel whose tone is on, the noise period and the mixer,
// per 50 Hz frame, at the best offset. A timer SID zeroes a voice's volume
// between the dump's samples, so for a SID tune Matt's rule (2026-09-13) is:
// periods 100%, and the only volume misses are voices the SNDH reads as 0.
//   1 BUZZ.YM == Jess/Sharpness_Buzztone.sndh: periods 97.5% (1500 frames),
//     vols A and C 100% and B 66% over 6000 (its buzz voice); it matched the
//     old .ymraw at 99.8% of register cells. FLAG ~ay.
//   2 150MPH (TAO of ACF, conv. Leonard) == Tao/Steps/150_mph.sndh: periods
//     100%; over 6000 frames every volume miss is a voice the SNDH reads as 0.
//   3 ANDROIDS (TAO of ACF, conv. Leonard) == Tao/Steps/Androids.sndh, its only
//     tune, offset 0, FLAG ~ady: periods 100% (1500 frames), audible periods and
//     mixer 100% over 3000; over all 8800 frames vol A 100% equal, B and C miss
//     only where the SNDH reads 0 (3747 + 4243 frames, its timer SID) bar 3
//     frames. The Mmh2 version: audible periods 7-22%, another arrangement.
//   5 LAP22_33.YM == Lap/Lap_33.sndh: periods 100%, volumes 100% over 6000
//     frames, at 24 frames' offset. FLAG ~y.
//   6 REALITY.YM (Big Alec, conv. Oedipus) == Big_Alec/Reality.sndh: periods
//     100%; over 6000 frames every volume miss is a voice the SNDH reads as 0.
//   4 SONG_025.YM "Drooling" (505, conv. aldn) has NO SNDH: the only one titled
//     so, 505/Drooling.sndh, is an STE DMA replay (~ey: silent here) of another
//     arrangement (7% of frames, audible periods 11-25%). The whole archive
//     (5,897 files, every subtune) scanned by periods in order (offsets
//     -60..400: best 23%, 505/TK_Machine) and out of order (the false hits,
//     e.g. Scy/TSCC_Mod_Compil_5, are 0% in order). So it stays the last-resort
//     YM dump until Matt picks otherwise.
// --------------------------------------------------------------------------
pub const TRACKS = [_][]const u8{
    "union/sharpness_buzztone.sndh",
    "union/150_mph.sndh",
    "union/androids.sndh",
    "union/Drooling.ymraw",
    "union/lap_33.sndh",
    "union/reality.sndh",
};
