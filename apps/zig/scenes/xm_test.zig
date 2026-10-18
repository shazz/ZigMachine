// --------------------------------------------------------------------------
// XM TEST: the minimal test screen for the FastTracker 2 player
// (libs/zig/players/xm*.zig), made to hear an XM on the board.
//
// Why a second XM screen: music_debug runs at about 1 fps on the board (its
// starfield, scope, logo and scroller), too slow to tell by ear what the sound
// CPU plays. This one is one plane of text, drawn only when something changes,
// so the cart costs nothing a frame and the music is all there is to hear.
//
// The songs are real modules from The Mod Archive, both by Drozerix and both
// Public Domain, so they may be bundled (docs/MUSIC.md "Bundled modules"):
//   1  keygen_9000.xm          "Keygen 9000", 8 channels, 55 KB, chiptune
//      https://modarchive.org/module.php?173938  md5 02b1f1dad70ea15a0b064c45468caa55
//   2  poppy_flower_girls.xm   "Poppy Flower Girls", 12 channels, 91 KB, demo style
//      (drozerix_-_poppy_flower_girls.xm on the archive, same bytes)
//      https://modarchive.org/module.php?175325  md5 251ef415c7e4a64b589f2fc3f86582df
//
// Keys 1-3 ask for a song BY NAME (zg.requestSong), key 4 stops it. They come in
// through setShadeMode, as the loader and the board's glass send digits 1-7
// (mode = digit - 1): no 0 reaches a cart, so stop is 4. local.xm is a song kept
// on its owner's machine only (gitignored, docs/MUSIC.md): a checkout without
// one plays nothing on 3.
//
// The player's refusal code (audioXmError) lives in the audio module, which no
// cart can reach, so the screen shows what the cart can read: the player mode
// mirrored into ZigOS (1: the Paula players, so the XM is playing; 0: nothing).
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

/// The songs keys 1..3 ask for, under docs/music/ (the board's song table is
/// built from these literals: fpga/tools/song_pack.py).
pub const SONGS = [_][]const u8{ "keygen_9000.xm", "poppy_flower_girls.xm", "local.xm" };
const LABELS = [_][]const u8{ "1  KEYGEN 9000         8 CH", "2  POPPY FLOWER GIRLS 12 CH", "3  LOCAL.XM          (OPTIONAL)" };
pub const STOP_MODE: u32 = SONGS.len; // key 4
const NONE: u8 = 0xFF;

pub const Demo = struct {
    selected: u8,
    shown_sel: u8,
    shown_mode: u8,
    drawn: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .selected = NONE, .shown_sel = NONE, .shown_mode = NONE, .drawn = false };
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPaletteEntry(BG, Color{ .r = 0, .g = 0, .b = 32, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 224, .g = 224, .b = 224, .a = 255 });
        fb.setPaletteEntry(SEL, Color{ .r = 224, .g = 192, .b = 64, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 128, .g = 128, .b = 160, .a = 255 });
    }

    /// Digits 1-7 from the host (mode = digit - 1): 1-3 play, 4 stops.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (mode < SONGS.len) {
            zg.requestSong(SONGS[mode]);
            self.selected = @intCast(mode);
        } else if (mode == STOP_MODE) {
            zg.stopSong();
            self.selected = NONE;
        }
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    /// Redraw only on a change: the selection, or the player mode the machine mirrors in.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const mode = zigos.audio_mode;
        if (self.drawn and self.shown_sel == self.selected and self.shown_mode == mode) return;
        self.drawn = true;
        self.shown_sel = self.selected;
        self.shown_mode = mode;
        const fb = &zigos.lfbs[PLANE];
        fb.clearFrameBuffer(BG);
        zigos.printText(fb, "ZIGMACHINE XM TEST", 16, 16, INK, BG);
        for (LABELS, 0..) |label, i| {
            const col = if (i == self.selected) SEL else INK;
            zigos.printText(fb, label, 16, 48 + @as(i16, @intCast(i)) * 14, col, BG);
        }
        zigos.printText(fb, "4  STOP", 16, 48 + 3 * 14, INK, BG);
        const name = if (self.selected == NONE) "NONE" else SONGS[self.selected];
        var buf: [40]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "SELECTED: {s}", .{name}) catch "SELECTED: ?";
        zigos.printText(fb, line, 16, 130, SEL, BG);
        const status = std.fmt.bufPrint(&buf, "PLAYER MODE {d}: {s}", .{ mode, modeText(mode) }) catch "?";
        zigos.printText(fb, status, 16, 144, DIM, BG);
        zigos.printText(fb, "MODE 0 AFTER A KEY: REFUSED OR MISSING", 16, 172, DIM, BG);
    }
};

fn modeText(mode: u8) []const u8 {
    return switch (mode) {
        0 => "SILENT",
        1 => "PAULA (XM PLAYING)",
        else => "ANOTHER PLAYER",
    };
}
