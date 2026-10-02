// The title ($13C) and F3's sound screen ($3DE): a Tiny picture faded in on a
// still screen (the VBL is a bare RTE), then SingSong -- Audio Visual Research's
// Quartet player, SINGSONG.PRG -- plays one of 520's four "Soundtracker" songs
// out of DUNE.PRG with the voice set SOUND2.SET, until Space.
//
// The tunes are dune_gen4_quartet.sndh: SingSong's own code, the voice set and
// the four songs, wrapped (prototypes/dune_gen4_re/quartet/). Its subtunes are
// the songs in DUNE.PRG's order:
//   1 $1DF2   F3's first song, and F5
//   2 $24F2   F3
//   3 $2A1E   F4
//   4 $3316   the title's, and F6
// SingSong starts once the fade is over (jsr 4 after jsr $3CD2), and the keys
// are read from ITS key byte, so nothing is taken before. A song key stops the
// song and starts the one it names from the top -- the same one again too.
const zg = @import("zigos");
const st = @import("st.zig");
const tny = @import("tny.zig");
const fade = @import("fade.zig");

pub const QUARTET = "dune_gen4_quartet.sndh";
pub const TITLE_SONG: u8 = 4;
pub const SOUND_SONG: u8 = 1;

const K_SPACE: u32 = 32;
/// F3..F6 on the sound screen ($456..$4E0: scancodes $3D..$40).
const SONG_KEYS = [_]struct { key: u32, song: u8 }{
    .{ .key = 0xE003, .song = 2 },
    .{ .key = 0xE004, .song = 3 },
    .{ .key = 0xE005, .song = 1 },
    .{ .key = 0xE006, .song = 4 },
};

pub const Still = struct {
    n: u32, // VBLs since the fade began
    song: u8, // what SingSong plays once the fade is over
    picks: bool, // F3..F6 change the song (the sound screen, not the title)
    palette: [16]u16,

    /// The picture is in the screen and the fade starts.
    pub fn enter(self: *Still, fb: *zg.LogicalFB, pic: *const tny.Picture, song: u8, picks: bool) void {
        self.* = .{ .n = 0, .song = song, .picks = picks, .palette = pic.palette };
        st.clear(fb);
        st.copyRows(fb, &pic.px, 0, 0, st.H);
    }

    /// SingSong plays, and reads the keys.
    pub fn playing(self: *const Still) bool {
        return self.n >= fade.SCREEN.frames();
    }

    pub fn vbl(self: *Still) void {
        self.n += 1;
        if (self.n == fade.SCREEN.frames()) zg.requestSongTune(QUARTET, self.song);
    }

    /// True when the key leaves (Space: SingSong's stop, jsr 8).
    pub fn key(self: *Still, cp: u32) bool {
        if (!self.playing()) return false;
        if (cp == K_SPACE) {
            zg.stopSong();
            return true;
        }
        if (!self.picks) return false;
        for (SONG_KEYS) |k| if (cp == k.key) {
            self.song = k.song;
            zg.requestSongTune(QUARTET, k.song);
        };
        return false;
    }

    pub fn render(self: *const Still) void {
        const pal = fade.at(&self.palette, self.n, fade.SCREEN);
        st.setPalette(&pal);
    }
};
