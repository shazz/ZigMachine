// --------------------------------------------------------------------------
// SID TEST: the test screen for the .sid player (libs/zig/players/sid.zig: a
// Commodore 64 PSID on cRSID, BARD's native C on the board, machine-audio.wasm
// on the page), the same shape as KT TEST: one text plane, drawn only when
// something changes, so the cart costs nothing a frame.
//
// Keys 1-4 are four classics from the High Voltage SID Collection, all PSID
// (cRSID's light engine plays them at 48-60 % of BARD, fpga/review/SID_BARD_STUDY.md).
// They are NOT ours to ship: like docs/music/local.xm they live on the owner's
// machine only, gitignored (fpga/tools/song_pack.py LOCAL_SONGS packs each one
// that is there, a clean checkout builds without them). Copy them from the
// study's set (prototypes/sid_re/tunes/, tools/sid_bard_fetch.sh) into docs/music/:
//   1  cybernoid_ii.sid  Jeroen Tel 1988, 6581, filter sweeps     md5 9d9613beda5d80beb7bf95628a64f470
//   2  wizball.sid       Martin Galway 1987, 6581, 4x (CIA) tune  md5 4522f889d5c41b3e08a00873a9e4b63a
//   3  commando.sid      Rob Hubbard 1985, 6581                   md5 6d019ecba831a9f853675aac29a61c10
//   4  club_style.sid    Jammer 2005, 8580, filter                md5 ac1dffc88b133b2f274b9fea33578ce0
// Each plays its file's default subtune (Wizball's is 4, the one the study measured).
// A tune that is not there leaves the player silent (the page's loadSid refuses the
// 404's bytes, the board's sound CPU says "ZM SONG MISSING"): after a second of
// silence the screen says so.
//
// Keys 6-7 are the shipped tune, HerMiniSID by Mihaly Horvath (Hermit), cRSID's
// own test tune, in libcRSID under its licence ("do what you want, mention me"):
// docs/music/hermini.sid and apps/zig/assets/sid/HERMINI.SID, 379 bytes,
// md5 537f693740ed05502fc23151381082d9; what apps/sid_test_check.mjs plays.
//   6  by name: zg.requestSong("hermini.sid"), the file the host fetches
//   7  by bytes: zg.requestSongBytes(.sid), the image in the cart's own memory,
//      as a C64 port reads its tune off its disk
//   5  stop
// Keys come in through setShadeMode (digit - 1): the loader and the glass send
// digits 1-7 only. Mode 7 (no key) asks for the same bytes as an RSID (magic
// "RSID", a real C64 program), which the player refuses: the harness's check.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const PLANE = 0;
const BG: u8 = 0;
const INK: u8 = 1;
const SEL: u8 = 2;
const DIM: u8 = 3;

/// Keys 1..4: the local HVSC tunes, under docs/music/ when the owner has them.
pub const LOCAL = [_][]const u8{ "cybernoid_ii.sid", "wizball.sid", "commando.sid", "club_style.sid" };
pub const SONG = "hermini.sid";
pub const TUNE = @embedFile("../assets/sid/HERMINI.SID");
/// The same tune as an RSID (a real C64 program): the player refuses it.
const RSID = blk: {
    var b: [TUNE.len]u8 = TUNE.*;
    b[0] = 'R';
    break :blk b;
};
const LABELS = [_][]const u8{
    "1  CYBERNOID II   TEL",   "2  WIZBALL        GALWAY", "3  COMMANDO       HUBBARD",
    "4  CLUB STYLE     JAMMER", "5  STOP",                  "6  HERMINISID BY NAME",
    "7  HERMINISID AS BYTES",
};
pub const STOP_MODE: u32 = 4; // key 5
pub const NAME_MODE: u32 = 5; // key 6
pub const BYTES_MODE: u32 = 6; // key 7
pub const RSID_MODE: u32 = 7; // no key: the harness's
const NONE: u8 = 0xFF;
/// Frames of silence after a local tune's request before the screen calls it absent.
const ABSENT_FRAMES: u32 = 60;

pub const Demo = struct {
    selected: u8,
    waited: u32, // frames since the request, while nothing plays
    shown_sel: u8,
    shown_mode: u8,
    shown_absent: bool,
    drawn: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .selected = NONE, .waited = 0, .shown_sel = NONE, .shown_mode = NONE, .shown_absent = false, .drawn = false };
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        // The C64's own blues: background $06, border/ink $0E (Pepto's palette).
        fb.setPaletteEntry(BG, Color{ .r = 53, .g = 40, .b = 121, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 112, .g = 164, .b = 178, .a = 255 });
        fb.setPaletteEntry(SEL, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 108, .g = 94, .b = 181, .a = 255 });
    }

    /// Digits 1-7 from the host (mode = digit - 1): 1-4 the local tunes, 5 stops, 6-7 HerMiniSID.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        switch (mode) {
            0...LOCAL.len - 1 => zg.requestSong(LOCAL[mode]),
            STOP_MODE => zg.stopSong(),
            NAME_MODE => zg.requestSong(SONG),
            BYTES_MODE => _ = zg.requestSongBytes(TUNE, .sid, 0),
            RSID_MODE => _ = zg.requestSongBytes(&RSID, .sid, 0),
            else => return,
        }
        self.selected = if (mode == STOP_MODE) NONE else @intCast(mode);
        self.waited = 0;
    }

    /// Count the silent frames after a request (a missing local tune never starts).
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (zigos.audio_mode != 0) self.waited = 0 else if (self.waited < ABSENT_FRAMES) self.waited += 1;
    }

    fn absent(self: *const Demo) bool {
        return self.selected < LOCAL.len and self.waited >= ABSENT_FRAMES;
    }

    /// Redraw only on a change: the selection, the player mode the machine mirrors in, absence.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const mode = zigos.audio_mode;
        const gone = self.absent();
        if (self.drawn and self.shown_sel == self.selected and self.shown_mode == mode and self.shown_absent == gone) return;
        self.drawn = true;
        self.shown_sel = self.selected;
        self.shown_mode = mode;
        self.shown_absent = gone;
        const fb = &zigos.lfbs[PLANE];
        fb.clearFrameBuffer(BG);
        zigos.printText(fb, "ZIGMACHINE SID TEST", 16, 16, SEL, BG);
        zigos.printText(fb, "CRSID BY HERMIT, ON BARD", 16, 28, DIM, BG);
        for (LABELS, 0..) |label, i| {
            const col = if (i == self.selected) SEL else INK;
            zigos.printText(fb, label, 16, 48 + @as(i16, @intCast(i)) * 12, col, BG);
        }
        zigos.printText(fb, "1-4 HVSC, LOCAL ONLY", 16, 136, DIM, BG);
        var buf: [40]u8 = undefined;
        const status = std.fmt.bufPrint(&buf, "PLAYER MODE {d}: {s}", .{ mode, modeText(mode) }) catch "?";
        zigos.printText(fb, status, 16, 156, DIM, BG);
        if (gone) zigos.printText(fb, "NOT ON THIS MACHINE", 16, 170, SEL, BG);
    }
};

fn modeText(mode: u8) []const u8 {
    return if (mode == 0) "SILENT" else "PLAYING";
}
