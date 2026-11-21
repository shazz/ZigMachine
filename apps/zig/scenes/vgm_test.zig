// --------------------------------------------------------------------------
// VGM TEST: the test screen for the .vgm / .vgz player (libs/zig/players/vgm.zig:
// a Mega Drive VGM on our own YM2612 + SN76489, libs/c/vgm, BARD's native C on
// the board, machine-audio.wasm on the page). One text plane, redrawn only when
// something shown changes (twice a second at most), so the cart costs nothing a
// frame.
//
// The tune is KESTREL FM, written by libs/c/vgm/make_tune.py for this repo (MIT,
// no third-party music): six FM channels (feedback bass, LFO-vibrato lead, pad,
// two arpeggios), the DAC on channel 6 for the drums, the PSG's square and
// noise. docs/music/kestrel_fm.vgm (100,038 bytes) and its gzip, .vgz (5,152).
//   1  by name: zg.requestSong("kestrel_fm.vgm")
//   2  by name: zg.requestSong("kestrel_fm.vgz"), inflated by the engine
//   3  by bytes: zg.requestSongBytes(.vgm) of the .vgz the cart carries
//      (apps/zig/assets/vgm/KESTREL_FM.VGZ), as a port reads its tune off its disk
//   4  stop
//   5-7  LOCAL Sonic 1 tunes (docs/music/sonic1_*.vgm, never committed): "NOT ON THIS MACHINE" without them
// Mode 7 (no key) asks for garbage bytes as a VGM, which the player refuses: the
// harness's check (apps/vgm_test_check.mjs). On the board the screen shows BARD's
// load (zg.mp3Status(.load): per mille of BARD, a second's mean of its renders,
// the OSD's figure); the page has none.
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

pub const SONG = "kestrel_fm.vgm";
pub const SONG_Z = "kestrel_fm.vgz";
pub const TUNE = @embedFile("../assets/vgm/KESTREL_FM.VGZ");
/// Keys 5-7: Sonic 1 tunes the owner keeps on their own machine only (docs/music/, gitignored; song_pack.py
/// LOCAL_SONGS packs each one that is there, a clean checkout builds without them). Copy them from the Gens
/// study's set: prototypes/gens_fm/dl/s1/x/ "02 - Green Hill Zone", "08 - Special Stage" (all six FM channels:
/// the load case), "06 - Star Light Zone".
pub const LOCAL = [_][]const u8{ "sonic1_ghz.vgm", "sonic1_special.vgm", "sonic1_starlight.vgm" };
const GARBAGE = [_]u8{ 'N', 'o', 't', ' ', 'a', ' ', 'V', 'G', 'M' } ** 8;
const LABELS = [_][]const u8{
    "1  KESTREL FM .VGM BY NAME", "2  KESTREL FM .VGZ BY NAME", "3  KESTREL FM AS BYTES",       "4  STOP",
    "5  SONIC 1 GREEN HILL (LOCAL)", "6  SONIC 1 SPECIAL STAGE (LOCAL)", "7  SONIC 1 STAR LIGHT (LOCAL)",
};
const NAMES = [_][]const u8{ "KESTREL FM", "KESTREL FM (VGZ)", "KESTREL FM (BYTES)", "", "GREEN HILL ZONE", "SPECIAL STAGE", "STAR LIGHT ZONE" };
pub const STOP_MODE: u32 = 3; // key 4
pub const BYTES_MODE: u32 = 2; // key 3
pub const LOCAL_MODE: u32 = 4; // keys 5-7
pub const GARBAGE_MODE: u32 = 7; // no key (digits 1-7 only reach a cart): the harness's
const NONE: u8 = 0xFF;
/// Frames of silence after a local tune's request before the screen calls it absent.
const ABSENT_FRAMES: u32 = 60;

pub const Demo = struct {
    selected: u8,
    frames: u32,
    shown: u32,
    peak: u32,
    waited: u32, // frames since the request, while nothing plays

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .selected = NONE, .frames = 0, .shown = 0xFFFF_FFFF, .peak = 0, .waited = 0 };
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPaletteEntry(BG, Color{ .r = 0, .g = 0, .b = 64, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 192, .g = 192, .b = 224, .a = 255 });
        fb.setPaletteEntry(SEL, Color{ .r = 255, .g = 224, .b = 64, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 96, .g = 128, .b = 224, .a = 255 });
        zg.requestSong(SONG); // plays from the start: the board's load readout needs no key
        self.selected = 0;
    }

    /// Digits 1-7 from the host (mode = digit - 1).
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        switch (mode) {
            0 => zg.requestSong(SONG),
            1 => zg.requestSong(SONG_Z),
            BYTES_MODE => _ = zg.requestSongBytes(TUNE, .vgm, 0),
            STOP_MODE => zg.stopSong(),
            LOCAL_MODE...LOCAL_MODE + LOCAL.len - 1 => zg.requestSong(LOCAL[mode - LOCAL_MODE]),
            GARBAGE_MODE => _ = zg.requestSongBytes(&GARBAGE, .vgm, 0),
            else => return,
        }
        self.selected = if (mode == STOP_MODE) NONE else @intCast(mode);
        self.peak = 0;
        self.waited = 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.frames +%= 1;
        if (zigos.audio_mode != 0) self.waited = 0 else if (self.waited < ABSENT_FRAMES) self.waited += 1;
    }

    /// A local tune asked for that never started: not on this machine (or not packed for this board).
    pub fn absent(self: *const Demo) bool {
        return self.selected >= LOCAL_MODE and self.selected < LOCAL_MODE + LOCAL.len and self.waited >= ABSENT_FRAMES;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.frames % 30 != 1) return;
        const load = zg.mp3Status(.load);
        if (load > self.peak and self.frames > 120) self.peak = load;
        const key = load << 16 ^ self.peak << 4 ^ @as(u32, self.selected) ^ @as(u32, zigos.audio_mode) << 12 ^
            @as(u32, @intFromBool(self.absent())) << 31;
        if (key == self.shown) return;
        self.shown = key;
        draw(self, zigos, load);
    }

    fn draw(self: *const Demo, zigos: *ZigOS, load: u32) void {
        const fb = &zigos.lfbs[PLANE];
        fb.clearFrameBuffer(BG);
        zigos.printText(fb, "ZIGMACHINE VGM TEST", 16, 16, SEL, BG);
        zigos.printText(fb, "YM2612 + SN76489, OUR OWN, ON BARD", 16, 28, DIM, BG);
        for (LABELS, 0..) |label, i| {
            const col = if (i == self.selected) SEL else INK;
            zigos.printText(fb, label, 16, 46 + @as(i16, @intCast(i)) * 11, col, BG);
        }
        const mode = zigos.audio_mode;
        const name = if (self.selected < NAMES.len) NAMES[self.selected] else "";
        var b0: [48]u8 = undefined;
        zigos.printText(fb, std.fmt.bufPrint(&b0, "{s}: {s}", .{ if (mode == 0) "SILENT" else "PLAYING", name }) catch "?", 16, 130, DIM, BG);
        if (self.absent()) zigos.printText(fb, "NOT ON THIS MACHINE", 16, 142, SEL, BG);
        if (load == 0) {
            zigos.printText(fb, "NO BARD LOAD FIGURE HERE", 16, 158, DIM, BG);
            return;
        }
        var b1: [40]u8 = undefined;
        zigos.printText(fb, std.fmt.bufPrint(&b1, "BARD LOAD {d}.{d} %", .{ load / 10, load % 10 }) catch "?", 16, 158, SEL, BG);
        var b2: [40]u8 = undefined;
        zigos.printText(fb, std.fmt.bufPrint(&b2, "PEAK      {d}.{d} %", .{ self.peak / 10, self.peak % 10 }) catch "?", 16, 170, INK, BG);
    }
};
