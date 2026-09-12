// --------------------------------------------------------------------------
// ST Replay — a homage to Microdeal's 8-bit sampler for the Atari ST, rebuilt on
// ZigMachine. The original is not a windowed GEM application: it is a single
// full-screen medium-res panel driven entirely from the keyboard, with a status
// strip and a waveform box. st_replay_ui.zig holds that layout (measured off a
// screenshot of the real 3.01 screen); this file is the state, the keyboard and
// the audio bridge.
//
// NOTE: the original's title line carries its authors' own copyright notice.
// This is a reimplementation, not their program, so it names itself and credits
// the original instead of reproducing that notice.
//
// Select in apps/zig/floppy.zig.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Blitter = zg.Blitter;
const gui = @import("rom").gui;
const ui = @import("st_replay_ui.zig");
const Rect = gui.Rect;

const WAVE_LEN: usize = 1280; // display resolution (host downsamples the .raw into it)
const PLAY_FRAMES: f32 = 60.0; // the bundled sample is ~1s, i.e. ~60 frames at 60fps

extern fn audioPlay() void;
extern fn audioStop() void;
extern fn loadSample(id: u32) void;

const FILES = [_][]const u8{ "SMP1.RAW", "SMP2.RAW" };

// Boot mode (read by scenes/gem_desktop.zig): false = launch from the desktop.
pub const BOOT_DIRECT = false;

pub const App = struct {
    blit: Blitter = .{},
    g: gui.Gui = undefined,
    dialog: gui.Dialog = .{},
    sample: [WAVE_LEN]u8 = [_]u8{128} ** WAVE_LEN, // signed 8-bit, 128 = zero
    rate: usize = 2, // index into ui.RATES; the real thing boots at 10 KHz
    playing: bool = false,
    looping: bool = false,
    monitor: bool = false,
    marked: bool = false,
    low: u32 = 0,
    high: u32 = 0,
    playhead: f32 = 0,
    wants_quit: bool = false,

    pub fn sampleBuf(self: *App) [*]u8 {
        return &self.sample;
    }
    pub fn sampleLen() usize {
        return WAVE_LEN;
    }

    pub fn init(self: *App, os: *ZigOS) void {
        const fb = &os.lfbs[0];
        self.blit.init();
        self.g = .{ .os = os, .fb = fb, .blit = &self.blit, .screen_w = ui.SW, .screen_h = ui.SH };
        // The app owns the whole screen: put the plane in MEDIUM res (the layout
        // is 640 wide) and install both palettes itself rather than inheriting
        // whatever the desktop left behind.
        fb.setResMedium();
        gui.installPalette(fb);
        ui.installPalette(fb);
        self.wants_quit = false;
        self.playing = false;
        self.rate = 2; // 10 KHz, as the original boots
        self.high = WAVE_LEN;
    }

    pub fn pointer(self: *App, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }

    // The whole program is the keyboard. Unknown keys are ignored, as in TOS.
    pub fn key(self: *App, cp: u32) void {
        if (self.dialog.active) return; // a dialog owns input while it is up
        if (cp >= ui.K_F1 and cp < ui.K_F1 + ui.ROWS) return self.fkey(cp - ui.K_F1);
        switch (cp) {
            'q', 'Q' => self.looping = !self.looping,
            'l', 'L' => self.dialog.openFiles("Load from disc", &FILES),
            's', 'S' => self.dialog.alert("Save to disc", "The disc is read-only."),
            'x', 'X' => self.wants_quit = true,
            'r', 'R' => self.reverse(),
            'w', 'W' => self.wipe(),
            ui.K_UNDO => { // RESET cursors
                self.low = 0;
                self.high = WAVE_LEN;
                self.marked = false;
            },
            ui.K_ESC => self.stop(),
            else => {},
        }
    }

    // f1..f6 pick the sample rate; f8 monitors; f10 replays.
    fn fkey(self: *App, n: usize) void {
        if (n < ui.RATE_ROWS) {
            self.rate = n;
        } else switch (n) {
            7 => self.monitor = !self.monitor, // f8
            9 => self.play(), // f10 = Replay
            else => {}, // f7 Magnify / f9 Sample need an input source we have none of
        }
    }

    fn play(self: *App) void {
        self.playing = true;
        self.playhead = 0;
        audioPlay();
    }
    fn stop(self: *App) void {
        self.playing = false;
        audioStop();
    }
    fn wipe(self: *App) void {
        @memset(&self.sample, 128);
        self.marked = false;
        self.stop();
    }
    fn reverse(self: *App) void {
        var i: usize = 0;
        while (i < WAVE_LEN / 2) : (i += 1) {
            const t = self.sample[i];
            self.sample[i] = self.sample[WAVE_LEN - 1 - i];
            self.sample[WAVE_LEN - 1 - i] = t;
        }
    }

    pub fn update(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.g.beginFrame();
        self.clicks();
        if (!self.playing) return;
        self.playhead += @as(f32, WAVE_LEN) / PLAY_FRAMES;
        if (self.playhead < WAVE_LEN) return;
        self.playhead = 0;
        if (self.looping) audioPlay() else self.playing = false;
    }

    // Every binding row is also a BUTTON: a click on it dispatches the row's own
    // key, so mouse and keyboard cannot drift apart (the frequency rows behaved
    // this way already; now the whole panel does).
    fn clicks(self: *App) void {
        if (!self.g.edge or self.dialog.active) return;
        var row: usize = 0;
        while (row < ui.ROWS) : (row += 1) {
            const y = ui.rowY(row);
            if (self.g.hit(ui.bindingRect(ui.LEFT[row], ui.COL_EQ[0], y))) return self.key(ui.LEFT[row].cp);
            if (self.g.hit(ui.bindingRect(ui.RIGHT[row], ui.COL_EQ[2], y))) return self.key(ui.RIGHT[row].cp);
        }
        for (ui.MID, 0..) |b, i| {
            if (self.g.hit(ui.bindingRect(b, ui.COL_EQ[1], ui.rowY(ui.MID_ROW0 + i)))) return self.key(b.cp);
        }
    }

    pub fn render(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        const g = &self.g;
        ui.desktop(g);
        self.drawPanel();
        self.drawStatus();
        self.drawWave();
        switch (self.dialog.process(g)) {
            .ok => |sel| if (self.dialog.filesel) {
                loadSample(sel); // the host swaps the sample + refreshes the display
                self.stop();
            },
            else => {},
        }
        g.endFrame();
    }

    fn drawPanel(self: *App) void {
        const g = &self.g;
        ui.panel(g, ui.PANEL);
        const cx = ui.PANEL.x + @divTrunc(ui.PANEL.w, 2);
        ui.centred(g, "ST Replay / Editor - ZigMachine", cx, ui.TITLE_ROW);

        var row: usize = 0;
        while (row < ui.ROWS) : (row += 1) {
            const y = ui.rowY(row);
            ui.binding(g, ui.LEFT[row], ui.COL_EQ[0], y, row == self.rate);
            ui.binding(g, self.rightRow(row), ui.COL_EQ[2], y, false);
        }
        ui.centred(g, ui.MID_HEADING, ui.COL_EQ[1] + 24, ui.rowY(0));
        for (ui.MID, 0..) |b, i| ui.binding(g, b, ui.COL_EQ[1], ui.rowY(ui.MID_ROW0 + i), false);
    }

    // The Loop row reports its state in the label, as the original does.
    fn rightRow(self: *const App, row: usize) ui.Binding {
        if (row != 0) return ui.RIGHT[row];
        return .{
            .key = ui.RIGHT[0].key,
            .what = if (self.looping) "Loop mode (ON)" else "Loop mode (OFF)",
            .cp = ui.RIGHT[0].cp,
        };
    }

    // The status strip: five fields, the 2nd and 4th in inverse video.
    fn drawStatus(self: *App) void {
        const g = &self.g;
        ui.panel(g, ui.STATUS);
        var buf: [40]u8 = undefined;
        var x = ui.STATUS.x + 3;
        const y = ui.STATUS.y + 2;
        const cell = @divTrunc(ui.STATUS.w - 6, 5);
        const fields = [5][]const u8{
            std.fmt.bufPrint(buf[0..12], "LOW : {d:>5}", .{self.low}) catch "LOW :",
            if (self.marked) "MARKED" else "UNMARKED",
            std.fmt.bufPrint(buf[12..26], "SIZE: {d:>7}", .{WAVE_LEN}) catch "SIZE:",
            if (self.monitor) "MONITOR" else "INTERNAL",
            std.fmt.bufPrint(buf[26..40], "HIGH: {d:>7}", .{self.high}) catch "HIGH:",
        };
        for (fields, 0..) |f, i| {
            const inv = i % 2 == 1;
            if (inv) g.rect(.{ .x = x, .y = y, .w = cell, .h = 8 }, gui.BLACK);
            g.text(f, x + 2, y, if (inv) gui.WHITE else gui.BLACK, if (inv) gui.BLACK else gui.WHITE);
            x += cell;
        }
    }

    fn drawWave(self: *App) void {
        const g = &self.g;
        ui.panel(g, ui.WAVE);
        const c = Rect{ .x = ui.WAVE.x + 2, .y = ui.WAVE.y + 2, .w = ui.WAVE.w - 4, .h = ui.WAVE.h - 4 };
        const half = @divTrunc(c.h, 2) - 1;
        var x: i16 = 0;
        while (x < c.w) : (x += 1) {
            const si: usize = @intCast(@divTrunc(@as(i32, x) * @as(i32, WAVE_LEN), c.w));
            const s8: i32 = @as(i8, @bitCast(self.sample[si]));
            const amp: i16 = @intCast(@divTrunc(s8 * @as(i32, half), 128));
            if (amp == 0) continue;
            const y0 = @min(ui.WAVE_MID, ui.WAVE_MID - amp);
            g.blit.fill(g.fb, c.x + x, y0, 1, @intCast(@abs(amp)), gui.BLACK);
        }
        g.blit.fill(g.fb, c.x, ui.WAVE_MID, @intCast(c.w), 1, ui.RED); // centre line
        if (!self.playing) return;
        const hx = c.x + @as(i16, @intFromFloat(self.playhead / @as(f32, WAVE_LEN) * @as(f32, @floatFromInt(c.w))));
        g.blit.fill(g.fb, hx, c.y, 1, @intCast(c.h), ui.RED); // playhead
    }
};
