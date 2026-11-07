// --------------------------------------------------------------------------
// SID TEST: the test screen for the .sid player (libs/zig/players/sid.zig: a
// Commodore 64 PSID on cRSID, BARD's native C on the board, machine-audio.wasm
// on the page), the same shape as KT TEST: one text plane, drawn only when
// something changes, so the cart costs nothing a frame.
//
// The tune is HerMiniSID by Mihaly Horvath (Hermit), cRSID's own test tune,
// shipped in libcRSID under its licence ("do what you want, mention me"):
// docs/music/hermini.sid and apps/zig/assets/sid/HERMINI.SID, 379 bytes,
// md5 537f693740ed05502fc23151381082d9.
//
//   1  by name: zg.requestSong("hermini.sid"), the file the host fetches
//   2  by bytes: zg.requestSongBytes(.sid), the image in the cart's own memory,
//      as a C64 port reads its tune off its disk
//   3  an RSID (the same bytes, magic "RSID"): refused, PSID only
//   5  stop
// Keys come in through setShadeMode (digit - 1), as KT TEST's do.
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

pub const SONG = "hermini.sid";
pub const TUNE = @embedFile("../assets/sid/HERMINI.SID");
/// The same tune as an RSID (a real C64 program): the player refuses it.
const RSID = blk: {
    var b: [TUNE.len]u8 = TUNE.*;
    b[0] = 'R';
    break :blk b;
};
const LABELS = [_][]const u8{ "1  HERMINISID BY NAME", "2  HERMINISID AS BYTES", "3  AN RSID (REFUSED)" };
pub const STOP_MODE: u32 = 4; // key 5
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
        // The C64's own blues: background $06, border/ink $0E (Pepto's palette).
        fb.setPaletteEntry(BG, Color{ .r = 53, .g = 40, .b = 121, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 112, .g = 164, .b = 178, .a = 255 });
        fb.setPaletteEntry(SEL, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 108, .g = 94, .b = 181, .a = 255 });
    }

    /// Digits 1-7 from the host (mode = digit - 1): 1-3 ask for the tune, 5 stops.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        switch (mode) {
            0 => zg.requestSong(SONG),
            1 => _ = zg.requestSongBytes(TUNE, .sid, 0),
            2 => _ = zg.requestSongBytes(&RSID, .sid, 0),
            STOP_MODE => zg.stopSong(),
            else => return,
        }
        self.selected = if (mode == STOP_MODE) NONE else @intCast(mode);
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
        zigos.printText(fb, "ZIGMACHINE SID TEST", 16, 16, SEL, BG);
        zigos.printText(fb, "CRSID BY HERMIT, ON BARD", 16, 28, DIM, BG);
        for (LABELS, 0..) |label, i| {
            const col = if (i == self.selected) SEL else INK;
            zigos.printText(fb, label, 16, 52 + @as(i16, @intCast(i)) * 14, col, BG);
        }
        zigos.printText(fb, "5  STOP", 16, 52 + 3 * 14, INK, BG);
        var buf: [40]u8 = undefined;
        const status = std.fmt.bufPrint(&buf, "PLAYER MODE {d}: {s}", .{ mode, modeText(mode) }) catch "?";
        zigos.printText(fb, status, 16, 138, DIM, BG);
    }
};

fn modeText(mode: u8) []const u8 {
    return if (mode == 0) "SILENT" else "PLAYING";
}
