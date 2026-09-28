// --------------------------------------------------------------------------
// ZIG mode's music: three ProTracker modules from The Mod Archive, one per
// situation, switched where the original switches its own music (MUSIC n /
// MUSIC OFF in the listing; sound.zig's music / musicEnd name the situation):
//
//   title   2350 the title (MUSIC 1 or 3), 150 the pause (MUSIC 1 or 3),
//           2260 the hall of fame (MUSIC 2), 1690 the newspaper (MUSIC 3);
//           the menus and briefings go on under the title's
//           -> "Explore the sky", BLuRry (1994), CC BY-SA 4.0
//   flying  1699 the briefing's end, 151 the pause's end (MUSIC OFF)
//           -> "The Hawk's Claw", Drozerix (2022), Public Domain
//   gameover  225 "You Were Killed !" / "No More Aircraft !" (MUSIC 2)
//           -> "dog75", Songerson (2019), CC BY 4.0
//   227 / 2281 (MUSIC OFF on the way back to the title): the title's.
//
// The files and their licences: docs/music/skystrike_music_CREDITS.txt.
// Each MOD is played at its situation's gain (zig_settings.zig music_gain_*,
// zg.requestModVolume), the flight's low under the effects.
// ORIGINAL plays skystrike.sndh exactly as before. The situation (and
// ORIGINAL's tune) is tracked in both modes, so Z switches the music to the
// other mode's for the moment the game is at. A situation's MOD already
// playing is not restarted (the title and the hall of fame share one).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hooks = @import("zig_hooks.zig");
const sound = @import("sound.zig");
const psg = @import("zig_psg.zig");
const set = @import("zig_settings.zig");

pub const Situation = enum(u8) { none, title, flying, gameover };

pub const MODS = std.EnumArray(Situation, []const u8).init(.{
    .none = "",
    .title = "skystrike_explore_the_sky.mod",
    .flying = "skystrike_the_hawks_claw.mod",
    .gameover = "skystrike_dog75.mod",
});

/// Where the game is, as ZIG's music sees it.
pub var now: Situation = .none;
/// ORIGINAL's tune (MUSIC n, 1-3), 0 while its music is off.
pub var sndh_tune: u8 = 0;
/// The MOD ZIG last requested (null: none since the SNDH or power-on).
pub var playing: ?Situation = null;
/// Gains zg.requestModVolume refused (the queue full, a setting outside
/// 0..1): checked 0 by the harness.
pub var refused: u32 = 0;

/// The music's level in situation `sit` (zig_settings.zig).
pub fn gain(sit: Situation) f32 {
    return switch (sit) {
        .none => 1.0,
        .title => set.music_gain_menus,
        .flying => set.music_gain_play,
        .gameover => set.music_gain_game_over,
    };
}

/// The game's MUSIC n at a switch point.
pub fn music(n: u8, sit: Situation) void {
    sndh_tune = n;
    now = sit;
    request();
}

/// The game's MUSIC OFF at a switch point: ZIG plays `next` from here.
pub fn off(next: Situation) void {
    sndh_tune = 0;
    now = next;
    request();
}

/// Z was pressed: the other mode's music for the same moment.
/// The load silences the YM: the engine note is replayed onto it.
pub fn switched(zig: bool) void {
    playing = null;
    if (zig) {
        request();
    } else {
        // ORIGINAL: skystrike.sndh, its tune restarted or its silence (a load
        // either way, which also ends the MOD, its effect and the PSG note).
        zg.requestSongTune(sound.NAME, if (sndh_tune != 0) sndh_tune else sound.SILENCE);
        sound.resident = true;
    }
    psg.replay(zig);
}

fn request() void {
    if (!hooks.zig or playing == now) return;
    playing = now;
    psg.invalidate();
    sound.resident = false; // the SNDH is gone: ORIGINAL's next command loads it
    if (now == .none) return zg.stopSong();
    zg.requestSong(MODS.get(now));
    if (!zg.requestModVolume(gain(now))) refused +%= 1;
}

pub fn reset() void {
    now = .none;
    sndh_tune = 0;
    playing = null;
    refused = 0;
}
