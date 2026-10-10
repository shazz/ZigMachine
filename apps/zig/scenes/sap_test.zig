// --------------------------------------------------------------------------
// SAP TEST — a jukebox for Atari 8-bit SAP tunes on the machine's POKEY.
//
// The test screen for the SAP player (libs/zig/players/sap*.zig, a 6502 driving
// machine/audio/pokey.zig): five ASMA tunes (sap_test/tunes.zig), one per row.
// Up/Down pick, Space/Enter (Fire) play, Left/Right step through the songs of a
// multi-song file and play the new one, keys 1-5 play a row directly. Escape
// leaves to the menu, as on every scene with no key() of its own (demo_main).
// Each play is zg.requestSongTune(<file>.sap, song), song counting from 1:
// never 0, which would mean the file's DEFSONG rather than the song shown.
//
// WHAT IS ALIVE. The cart cannot see the POKEY: the machine mirrors only the YM
// registers, the Paula scopes and the player MODE into ZigOS (demo_main's
// getYmRegsPointer / getScopesPointer / getAudioModePointer), and no ABI is
// invented here for one test screen. So the screen shows the one real thing it
// can read, audio_mode == 5 (the SAP player running), the song's elapsed time
// against its SAP TIME tag, and a credits scroller whose ink is a REAL raster:
// one palette entry rewritten per scanline from the plane's HBL handler.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const tunes = @import("sap_test/tunes.zig");
const TUNES = tunes.TUNES;
const raster = @import("sap_test/raster.zig");

const PLANE = 0;
const AUDIO_MODE_SAP: u8 = 5; // apps/zig/demo_audio_sap.zig
// plane 0 palette
const BG: u8 = 0;
const INK: u8 = 1;
const CURSOR: u8 = 2;
const SUB: u8 = 3;
const DIM: u8 = 4;
const PLAY: u8 = 5; // pulsed each frame
const SCROLL = raster.SCROLL; // rewritten per scanline by raster.handler
const TITLE: u8 = 7;

const COLS = 40; // 320 px of 8x8 font
const LIST_Y: i16 = 34;
const ROW_H: i16 = 21;
const STATUS_Y: i16 = 146;
const HELP_Y: i16 = 170;
const SCROLL_Y: i16 = 184;

/// A 40-column text row, space-filled: fields are placed at fixed columns.
const Row = struct {
    buf: [COLS]u8 = [_]u8{' '} ** COLS,

    fn put(self: *Row, col: usize, text: []const u8) void {
        const n = @min(text.len, COLS - col);
        @memcpy(self.buf[col..][0..n], text[0..n]);
    }
    fn print(self: *Row, col: usize, comptime fmt: []const u8, args: anytype) void {
        var tmp: [COLS]u8 = undefined;
        self.put(col, std.fmt.bufPrint(&tmp, fmt, args) catch return);
    }
};

pub const Demo = struct {
    cursor: usize,
    songs: [TUNES.len]u8, // the song shown per tune, from 1
    playing: usize,
    play_ms: f32,
    scroll_px: u32,
    pulse: f32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.cursor = 0;
        self.songs = [_]u8{1} ** TUNES.len;
        self.scroll_px = 0;
        self.pulse = 0;
        raster.offset = 0;
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPaletteEntry(BG, Color{ .r = 8, .g = 12, .b = 40, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 236, .g = 236, .b = 244, .a = 255 });
        fb.setPaletteEntry(CURSOR, Color{ .r = 255, .g = 214, .b = 80, .a = 255 });
        fb.setPaletteEntry(SUB, Color{ .r = 120, .g = 200, .b = 240, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 120, .g = 124, .b = 150, .a = 255 });
        fb.setPaletteEntry(TITLE, Color{ .r = 255, .g = 128, .b = 64, .a = 255 });
        fb.setPaletteEntry(SCROLL, raster.COPPER[0]);
        fb.setFrameBufferHBLHandler(0, raster.handler);
        fb.clearFrameBuffer(BG);
        self.play(0); // a screen starts with its music: the first tune
    }

    fn play(self: *Demo, i: usize) void {
        zg.requestSongTune(TUNES[i].file, self.songs[i]);
        self.playing = i;
        self.play_ms = 0;
    }

    /// Host input: 0 up, 1 down, 2 left, 3 right, 5 fire (Space/Enter).
    pub fn input(self: *Demo, dir: u8) void {
        const n = TUNES.len;
        switch (dir) {
            0 => self.cursor = (self.cursor + n - 1) % n,
            1 => self.cursor = (self.cursor + 1) % n,
            2, 3 => self.stepSong(dir == 3),
            5 => self.play(self.cursor),
            else => {},
        }
    }

    fn stepSong(self: *Demo, forward: bool) void {
        const count: u8 = @intCast(TUNES[self.cursor].times.len);
        if (count < 2) return; // one song: nothing to step to, and nothing restarted
        const s = &self.songs[self.cursor];
        s.* = if (forward) s.* % count + 1 else (s.* + count - 2) % count + 1;
        self.play(self.cursor);
    }

    /// Keys 1-5 (the host forwards 1-7 here): play that row.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (mode >= TUNES.len) return;
        self.cursor = mode;
        self.play(mode);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (dt > 0 and dt < 1000) self.play_ms += dt;
        self.scroll_px +%= 1;
        raster.offset +%= 1;
        self.pulse += 0.12;
        if (self.pulse > 2 * std.math.pi) self.pulse -= 2 * std.math.pi; // bounded: sin() keeps its precision
        const g: f32 = 0.6 + 0.4 * @sin(self.pulse);
        zigos.lfbs[PLANE].setPaletteEntry(PLAY, Color{ .r = @intFromFloat(90 * g), .g = @intFromFloat(255 * g), .b = @intFromFloat(120 * g), .a = 255 });
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        fb.clearFrameBuffer(BG);
        zigos.printText(fb, "ZIGMACHINE POKEY - SAP TEST", 52, 6, TITLE, BG);
        zigos.printText(fb, "ATARI 8-BIT TUNES FROM ASMA", 52, 18, DIM, BG);
        for (TUNES, 0..) |t, i| self.drawTune(zigos, fb, t, i);
        self.drawStatus(zigos, fb);
        zigos.printText(fb, "UP/DN PICK  FIRE PLAY  L/R SONG  ESC", 16, HELP_Y, DIM, BG);
        self.drawScroller(zigos, fb);
    }

    fn drawTune(self: *Demo, zigos: *ZigOS, fb: *LogicalFB, t: tunes.Tune, i: usize) void {
        const y = LIST_Y + @as(i16, @intCast(i)) * ROW_H;
        const selected = i == self.cursor;
        var top = Row{};
        top.put(0, if (selected) ">" else " ");
        top.put(2, t.title);
        top.put(22, t.year);
        top.put(27, if (t.pal) "PAL" else "NTSC");
        var sub = Row{};
        sub.put(2, t.composer);
        sub.print(22, "TYPE {c}", .{t.sap_type});
        sub.print(30, "SONG {d}/{d}", .{ self.songs[i], t.times.len });
        zigos.printText(fb, &top.buf, 8, y, if (selected) CURSOR else INK, BG);
        if (i == self.playing) zigos.printText(fb, "PLAY", 8 + 33 * 8, y, PLAY, BG);
        zigos.printText(fb, &sub.buf, 8, y + 9, SUB, BG);
    }

    fn drawStatus(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const t = TUNES[self.playing];
        const secs: u32 = @intFromFloat(self.play_ms / 1000);
        var row = Row{};
        row.print(0, "{s} {d}/{d}", .{ t.title, self.songs[self.playing], t.times.len });
        row.print(24, "{d}:{d:0>2} / {s}", .{ secs / 60, secs % 60, t.times[self.songs[self.playing] - 1] });
        zigos.printText(fb, &row.buf, 8, STATUS_Y, INK, BG);
        // The machine's own word on it: the audio thread's player mode, mirrored in.
        const running = zigos.audio_mode == AUDIO_MODE_SAP;
        const msg = if (running) "POKEY: 6502 SAP PLAYER RUNNING" else "POKEY: SILENT (SOUND ON TO HEAR IT)";
        zigos.printText(fb, msg, 8, STATUS_Y + 10, if (running) PLAY else DIM, BG);
    }

    fn drawScroller(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const text = tunes.CREDITS;
        const span = (text.len + COLS) * 8;
        const x0: i32 = 320 - @as(i32, @intCast(self.scroll_px % span));
        for (text, 0..) |c, k| {
            const x = x0 + @as(i32, @intCast(k * 8));
            if (x <= -8 or x >= 320) continue;
            const wob: i32 = @intFromFloat(@sin(@as(f32, @floatFromInt(x)) * 0.04 + self.pulse) * 3);
            zigos.printText(fb, &[_]u8{c}, @intCast(x), @intCast(SCROLL_Y + 4 + wob), SCROLL, BG);
        }
    }
};
