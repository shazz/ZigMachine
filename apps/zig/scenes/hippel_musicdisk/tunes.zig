// --------------------------------------------------------------------------
// The ten keys ($04E2): 'a'..'j' (the raw CIA bytes $BF $95 $99 $BB $DB $B9 $B7
// $B5 $D1 $B3) each point the replay at one of five modules and INIT it with a
// song number. 'i' is what the demo starts with ($00C6). Five modules, ten tunes:
// Fred took several songs out of the multi-song Warp and Thalion modules.
//
// Every module plays on ONE replay, modland's Rings of Medusa player (the demo
// patched its `lea TFMX(pc)` into a pointer). docs/music/hippel/*.hip are that
// player, unpatched, + each module's bytes off the disk: what the demo plays
// (prototypes/hippel_musicdisk_re/NOTES.md, tools/mkhip.py).
//   warp_title.hip       md5 797bf405..  modland "warp (title)" = a prefix of it
//   warp_ingame2.hip     md5 98b1c096..  modland "warp (ingame 2)" = a prefix
//   warp_ingame1.hip     md5 36bc4a50..  modland "warp (ingame 1)" = a prefix
//   thalion_intro.hip    md5 2a6f6c0a..  modland "thalion intro": same size, another build
//   rings_of_medusa.hip  md5 024e14d6..  modland "rings of medusa.hip" as is (the
//                                        disk's copy is cut 172 bytes short)
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const Tune = struct { file: []const u8, song: u8 };

pub const KEYS = [10]Tune{
    .{ .file = "hippel/warp_title.hip", .song = 1 }, // a
    .{ .file = "hippel/warp_ingame2.hip", .song = 1 }, // b
    .{ .file = "hippel/warp_ingame2.hip", .song = 2 }, // c
    .{ .file = "hippel/warp_ingame1.hip", .song = 2 }, // d
    .{ .file = "hippel/warp_ingame1.hip", .song = 3 }, // e
    .{ .file = "hippel/warp_ingame1.hip", .song = 4 }, // f
    .{ .file = "hippel/thalion_intro.hip", .song = 1 }, // g
    .{ .file = "hippel/thalion_intro.hip", .song = 2 }, // h
    .{ .file = "hippel/rings_of_medusa.hip", .song = 1 }, // i
    .{ .file = "hippel/rings_of_medusa.hip", .song = 2 }, // j
};
pub const START: u8 = 8; // 'i'

pub var current: u8 = START;

/// The original stops the replay (d0 = 0), points it at the module and INITs
/// the song: here one request, which reloads and starts the tune. (The Amiga
/// read the keyboard's last byte every frame, so a held key restarted the tune
/// until released; a key here starts it once, on the press.)
pub fn select(k: u8) void {
    current = k;
    zg.requestSongTune(KEYS[k].file, KEYS[k].song);
}
