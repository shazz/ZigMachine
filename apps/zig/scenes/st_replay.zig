// --------------------------------------------------------------------------
// ST Replay — a GEM-style windowed sample player, the first app built on the
// ZigOS GUI toolkit (zigos/gui.zig). A tribute to Microdeal's ST Replay.
//
// A GEM desktop + menu bar, two draggable windows (a sample waveform display and
// a transport panel with Play/Stop/Rec/Loop bevel buttons), all driven by the
// mouse (host demo.pointer). Play scrubs a playhead across the waveform; audio
// hookup to the sample worklet is left as a follow-up (this is the UI + WM).
//
// Select in apps/floppy.zig.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;
const gui = @import("rom").gui;
const Rect = gui.Rect;

const WAVE_LEN: usize = 1280; // display resolution of the sample (host downsamples smp1.raw into it)
const PLAY_FRAMES: f32 = 60.0; // smp1 is ~1s (12517 @ 12517Hz), i.e. ~60 frames at 60fps
const SW: i16 = 640; // medium-res screen width
const SH: i16 = 200;

const MENUS = [_]gui.Menu{
    .{ .title = "Desk", .items = &.{.{ .label = "About ST Replay" }} },
    .{ .title = "File", .items = &.{ .{ .label = "Load..." }, .{ .label = "Save..." }, .{ .label = "Quit" } } },
    .{ .title = "Sound", .items = &.{ .{ .label = "Play" }, .{ .label = "Stop" }, .{ .label = "Loop" } } },
    .{ .title = "Options", .items = &.{ .{ .label = "8 bit" }, .{ .label = "12.5 kHz" } } },
};

// Host audio bridge (wired in sealed-loader.js): play/stop/select the sample.
extern fn audioPlay() void;
extern fn audioStop() void;
extern fn loadSample(id: u32) void;

const FILES = [_][]const u8{ "SMP1.RAW", "SMP2.RAW" };

// Boot mode (read by scenes/gem_desktop.zig): false = show the GEM desktop and
// launch this app from its icon; true = boot straight into the app (skip the
// desktop). File > Quit returns to the desktop either way.
pub const BOOT_DIRECT = false;

pub const App = struct {
    blit: Blitter = .{},
    g: gui.Gui = undefined,
    wm: gui.Wm = .{},
    menubar: gui.MenuBar = .{},
    dialog: gui.Dialog = .{},
    w_sample: u8 = 0,
    w_transport: u8 = 0,
    sample: [WAVE_LEN]u8 = [_]u8{128} ** WAVE_LEN, // signed 8-bit (128=zero); host fills from smp1.raw
    playing: bool = false,
    looping: bool = false,
    recording: bool = false,
    playhead: f32 = 0,
    wants_quit: bool = false, // set by File > Quit; the host (GEM desktop) returns to the desktop

    // Exposed to the host so it can copy the real sample in for display.
    pub fn sampleBuf(self: *App) [*]u8 {
        return &self.sample;
    }
    pub fn sampleLen() usize {
        return WAVE_LEN;
    }

    // The GEM desktop (host) owns the medium plane, palette and background; the app
    // just sets up its GUI + windows. Called once; launching only flips it visible.
    pub fn init(self: *App, os: *ZigOS) void {
        const fb = &os.lfbs[0];
        self.blit.init();
        self.g = .{ .os = os, .fb = fb, .blit = &self.blit, .screen_w = SW, .screen_h = SH };
        self.wants_quit = false;
        self.playing = false;
        if (self.wm.n == 0) { // add windows once
            self.w_sample = self.wm.add(.{ .r = .{ .x = 16, .y = 26, .w = 440, .h = 120 }, .title = "SAMPLE.SPL" });
            self.w_transport = self.wm.add(.{ .r = .{ .x = 380, .y = 150, .w = 236, .h = 44 }, .title = "Transport" });
        }
    }

    pub fn pointer(self: *App, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }

    pub fn update(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.g.beginFrame();
        if (!self.dialog.active) _ = self.wm.handle(&self.g); // dialog is modal
        if (self.playing) {
            self.playhead += @as(f32, WAVE_LEN) / PLAY_FRAMES; // scrub in sync with the ~1s sample
            if (self.playhead >= WAVE_LEN) {
                self.playhead = 0;
                if (self.looping) audioPlay() else self.playing = false; // loop = re-trigger
            }
        }
    }

    pub fn render(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        const g = &self.g;
        g.rect(.{ .x = 0, .y = 0, .w = SW, .h = SH }, gui.DESK); // desktop

        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open) continue;
            const active = id == self.wm.topId();
            const content = self.wm.drawChrome(g, id, active);
            if (id == self.w_sample) self.drawWave(content) else self.drawTransport(content);
        }
        // menu bar (inert while a dialog is up), then any modal dialog on top.
        if (self.menubar.process(g, &MENUS, SW, self.dialog.active)) |pick| self.onMenu(pick);
        switch (self.dialog.process(g)) {
            .ok => |sel| if (self.dialog.filesel) {
                loadSample(sel); // the host swaps the sample + refreshes the display
                self.playing = false;
            },
            else => {},
        }
        g.endFrame();
    }

    fn onMenu(self: *App, pick: gui.MenuPick) void {
        switch (pick.menu) {
            0 => self.dialog.alert("About", "ST Replay - ZigMachine GEM"), // Desk
            1 => switch (pick.item) { // File
                0 => self.dialog.openFiles("Load Sample", &FILES),
                2 => self.wants_quit = true, // Quit -> back to the GEM desktop (eject the cartridge)
                else => {},
            },
            2 => switch (pick.item) { // Sound
                0 => {
                    self.playing = true;
                    self.playhead = 0;
                    audioPlay();
                },
                1 => {
                    self.playing = false;
                    audioStop();
                },
                2 => self.looping = !self.looping,
                else => {},
            },
            else => {},
        }
    }

    fn drawWave(self: *App, c: Rect) void {
        const g = &self.g;
        g.rect(c, gui.BLACK); // scope background
        const mid = c.y + @divTrunc(c.h, 2);
        g.blit.fill(g.fb, c.x, mid, @intCast(c.w), 1, gui.DGRAY); // zero line
        var x: i16 = 0;
        while (x < c.w) : (x += 1) {
            const si: usize = @intCast(@divTrunc(@as(i32, x) * @as(i32, WAVE_LEN), c.w));
            const s8: i32 = @as(i8, @bitCast(self.sample[si])); // signed 8-bit sample (-128..127)
            const amp: i16 = @intCast(@divTrunc(s8 * @as(i32, @divTrunc(c.h, 2) - 2), 128));
            const y0 = @min(mid, mid - amp);
            const h = @abs(amp) + 1;
            g.blit.fill(g.fb, c.x + x, y0, 1, @intCast(h), gui.WAVE);
        }
        if (self.playing) { // playhead
            const hx = c.x + @as(i16, @intFromFloat(self.playhead / @as(f32, WAVE_LEN) * @as(f32, @floatFromInt(c.w))));
            g.blit.fill(g.fb, hx, c.y, 1, @intCast(c.h), gui.ACCENT);
        }
    }

    fn drawTransport(self: *App, c: Rect) void {
        const g = &self.g;
        const bw: i16 = 52;
        const y = c.y + 6;
        if (g.button(.{ .x = c.x + 4, .y = y, .w = bw, .h = 20 }, "PLAY", self.playing)) {
            self.playing = true;
            self.playhead = 0;
            audioPlay(); // real sound via the sample worklet
        }
        if (g.button(.{ .x = c.x + 4 + bw + 2, .y = y, .w = bw, .h = 20 }, "STOP", false)) {
            self.playing = false;
            audioStop();
        }
        if (g.button(.{ .x = c.x + 4 + (bw + 2) * 2, .y = y, .w = bw, .h = 20 }, "REC", self.recording)) {
            self.recording = !self.recording;
        }
        if (g.button(.{ .x = c.x + 4 + (bw + 2) * 3, .y = y, .w = bw, .h = 20 }, "LOOP", self.looping)) {
            self.looping = !self.looping;
        }
    }
};
