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
const draw = @import("st_replay_draw.zig");
const Rect = gui.Rect;

const WAVE_LEN: usize = 1280; // display resolution (host downsamples the .raw into it)

// The host plays the loaded sample at the rate we ask for, so f1..f6 really do
// change the replay frequency (0 would mean "the sample's own rate").
extern fn audioPlay(hz: u32) void;
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
    // The REAL length of the loaded sample in bytes. The host downsamples it
    // into `sample` for display, so the display buffer's size says nothing about
    // the sample — every count the panel reports comes from here.
    bytes: u32 = 0,
    hz: u32 = 0, // its playback rate, so the view has a real TIME axis
    playhead: f32 = 0,
    wants_quit: bool = false,

    pub fn sampleBuf(self: *App) [*]u8 {
        return &self.sample;
    }
    pub fn sampleLen() usize {
        return WAVE_LEN;
    }
    // The host reports what the loaded sample really is — its byte count and its
    // playback rate (see loadSampleForDisplay in docs/sealed-loader.js). Both are
    // needed: the panel counts bytes, and the playhead has to cross the display
    // in the sample's own DURATION rather than in some fixed number of frames.
    pub fn setSampleBytes(self: *App, n: u32, hz: u32) void {
        self.bytes = n;
        self.hz = hz;
        self.high = n;
        self.low = 0;
    }

    // Seconds of audio in the loaded sample (0 when nothing is loaded).
    fn duration(self: *const App) f32 {
        const hz = ui.RATES[self.rate]; // replaying faster makes the sample shorter
        if (self.bytes == 0 or hz == 0) return 0;
        return @as(f32, @floatFromInt(self.bytes)) / @as(f32, @floatFromInt(hz));
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
        self.high = self.bytes;
    }

    // Everything the screen needs to draw itself, and nothing else.
    fn view(self: *const App) draw.View {
        return .{
            .rate = self.rate,
            .looping = self.looping,
            .monitor = self.monitor,
            .marked = self.marked,
            .playing = self.playing,
            .playhead = self.playhead,
            .low = self.low,
            .high = self.high,
            .bytes = self.bytes,
            .sample = &self.sample,
        };
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
            'x', 'X' => { // eXit: never leave the sound running behind us
                self.stop();
                self.wants_quit = true;
            },
            'r', 'R' => self.reverse(),
            'w', 'W' => self.wipe(),
            ui.K_UNDO => { // RESET cursors
                self.low = 0;
                self.high = self.bytes;
                self.marked = false;
            },
            ui.K_ESC => self.stop(),
            else => {},
        }
    }

    // Arrow keys walk the selection — the highlighted replay rate — the way the
    // function keys jump straight to one. Wraps, so holding a direction cycles.
    pub fn input(self: *App, dir: u32) void {
        if (self.dialog.active) return;
        switch (dir) {
            0 => self.rate = (self.rate + ui.RATE_ROWS - 1) % ui.RATE_ROWS, // up
            1 => self.rate = (self.rate + 1) % ui.RATE_ROWS, // down
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

    // Nothing to replay until a sample has been loaded — Replay is a no-op on an
    // empty machine rather than a silent "playing" state.
    fn play(self: *App) void {
        if (self.bytes == 0) return;
        self.playing = true;
        self.playhead = 0;
        audioPlay(ui.RATES[self.rate]);
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
        self.g.beginFrame();
        self.clicks();
        if (!self.playing) return;
        // The playhead crosses the display in the sample's own running time, so
        // the view's x axis really is the sample's time axis. `dt` is in ms.
        const secs = self.duration();
        if (secs <= 0) return;
        self.playhead += @as(f32, WAVE_LEN) * (dt / 1000.0) / secs;
        if (self.playhead < WAVE_LEN) return;
        self.playhead = 0;
        if (self.looping) audioPlay(ui.RATES[self.rate]) else self.playing = false;
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
        draw.screen(g, self.view());
        switch (self.dialog.process(g)) {
            .ok => |sel| if (self.dialog.filesel) {
                loadSample(sel); // the host swaps the sample + refreshes the display
                self.stop();
            },
            else => {},
        }
        g.endFrame();
    }

};
