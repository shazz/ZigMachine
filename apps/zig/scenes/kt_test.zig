// --------------------------------------------------------------------------
// KT TEST: the minimal test screen for a klystrack (.kt) song player on BARD,
// the same shape as XM TEST (xm_test.zig): one text plane, drawn only when
// something changes, so the cart costs nothing a frame.
//
// The songs play on the .kt player (libs/zig/players/kt.zig: klystron's cyd in
// integer Zig on the four Paula channels), in the browser and on BARD alike;
// the player mode reads 1 while one plays.
//
// The songs are klystrack's own example songs, from upstream (kometbomb/klystrack,
// MIT like the port, apps/ports/klystrack/LICENSE and README.md), copied from
// apps/ports/klystrack/data/*.KT with lower-case names into docs/music/:
//   1  starport2.kt      1822 B  md5 0246c50252e717ea7677fefb5c044ea4
//   2  castlevania.kt    2793 B  md5 9657f6b0554d8df5548bb35c3f91cef5
//   3  oceanloader3.kt   8144 B  md5 22139dc5dbaf6df1ec72b35b2db25775
//   4  dpintro.kt        9725 B  md5 eaee7e7520571ce27a857b7edcd58e68
//
// Keys 1-4 ask for a song BY NAME (zg.requestSong), key 5 stops it. They come in
// through setShadeMode, as the loader and the board's glass send digits 1-7
// (mode = digit - 1): no 0 reaches a cart, so stop is 5.
//
// The screen shows what the cart can read: the player mode the machine mirrors
// into ZigOS (0: nothing plays).
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

/// The songs keys 1..4 ask for, under docs/music/.
pub const SONGS = [_][]const u8{ "starport2.kt", "castlevania.kt", "oceanloader3.kt", "dpintro.kt" };
const LABELS = [_][]const u8{ "1  STARPORT2", "2  CASTLEVANIA", "3  OCEANLOADER3", "4  DPINTRO" };
pub const STOP_MODE: u32 = SONGS.len; // key 5
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

    /// Digits 1-7 from the host (mode = digit - 1): 1-4 ask for a song, 5 stops.
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
        zigos.printText(fb, "ZIGMACHINE KT TEST", 16, 16, INK, BG);
        for (LABELS, 0..) |label, i| {
            const col = if (i == self.selected) SEL else INK;
            zigos.printText(fb, label, 16, 48 + @as(i16, @intCast(i)) * 14, col, BG);
        }
        zigos.printText(fb, "5  STOP", 16, 48 + 4 * 14, INK, BG);
        const name = if (self.selected == NONE) "NONE" else SONGS[self.selected];
        var buf: [40]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "SELECTED: {s}", .{name}) catch "SELECTED: ?";
        zigos.printText(fb, line, 16, 138, SEL, BG);
        const status = std.fmt.bufPrint(&buf, "PLAYER MODE {d}: {s}", .{ mode, modeText(mode) }) catch "?";
        zigos.printText(fb, status, 16, 152, DIM, BG);
    }
};

fn modeText(mode: u8) []const u8 {
    return if (mode == 0) "SILENT" else "A PLAYER IS ACTIVE";
}
