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
const gui = zg.gui;
const Rect = gui.Rect;

const WAVE_LEN: usize = 1024;

pub const Demo = struct {
    blit: Blitter = .{},
    g: gui.Gui = undefined,
    wm: gui.Wm = .{},
    w_sample: u8 = 0,
    w_transport: u8 = 0,
    sample: [WAVE_LEN]f32 = undefined,
    playing: bool = false,
    looping: bool = false,
    recording: bool = false,
    playhead: f32 = 0,

    pub fn init(self: *Demo, os: *ZigOS) void {
        const fb = &os.lfbs[0];
        fb.is_enabled = true;
        self.blit.init();
        gui.installPalette(fb);
        os.setBackgroundColor(.{ .r = 0, .g = 150, .b = 90, .a = 255 }); // desktop green in the border
        self.g = .{ .os = os, .fb = fb, .blit = &self.blit };

        self.w_sample = self.wm.add(.{ .r = .{ .x = 8, .y = 24, .w = 210, .h = 96 }, .title = "SAMPLE.SPL" });
        self.w_transport = self.wm.add(.{ .r = .{ .x = 150, .y = 128, .w = 160, .h = 58 }, .title = "Transport" });
        self.genSample();
    }

    // A synthetic sample: a couple of decaying sine bursts (something to draw).
    fn genSample(self: *Demo) void {
        for (&self.sample, 0..) |*s, i| {
            const t: f32 = @floatFromInt(i);
            const env = @exp(-t / 380.0) + 0.5 * @exp(-@abs(t - 520.0) / 90.0);
            s.* = env * (@sin(t * 0.10) + 0.4 * @sin(t * 0.31));
        }
    }

    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.g.beginFrame();
        self.wm.handle(&self.g);
        if (self.playing) {
            self.playhead += 6.0;
            if (self.playhead >= WAVE_LEN) {
                self.playhead = 0;
                if (!self.looping) self.playing = false;
            }
        }
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        const g = &self.g;
        g.rect(.{ .x = 0, .y = 0, .w = 320, .h = 200 }, gui.DESK); // desktop
        self.menuBar();

        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open) continue;
            const active = id == self.wm.topId();
            const content = self.wm.drawChrome(g, id, active);
            if (id == self.w_sample) self.drawWave(content) else self.drawTransport(content);
        }
        g.endFrame();
    }

    fn menuBar(self: *Demo) void {
        const g = &self.g;
        g.rect(.{ .x = 0, .y = 0, .w = 320, .h = 10 }, gui.WHITE);
        g.blit.fill(g.fb, 0, 10, 320, 1, gui.BLACK);
        g.text(" Desk  File  Sound  Options", 4, 1, gui.BLACK, gui.WHITE);
    }

    fn drawWave(self: *Demo, c: Rect) void {
        const g = &self.g;
        g.rect(c, gui.BLACK); // scope background
        const mid = c.y + @divTrunc(c.h, 2);
        g.blit.fill(g.fb, c.x, mid, @intCast(c.w), 1, gui.DGRAY); // zero line
        var x: i16 = 0;
        while (x < c.w) : (x += 1) {
            const si: usize = @intCast(@divTrunc(@as(i32, x) * @as(i32, WAVE_LEN), c.w));
            const amp: i16 = @intFromFloat(self.sample[si] * @as(f32, @floatFromInt(@divTrunc(c.h, 2) - 2)));
            const y0 = @min(mid, mid - amp);
            const h = @abs(amp) + 1;
            g.blit.fill(g.fb, c.x + x, y0, 1, @intCast(h), gui.WAVE);
        }
        if (self.playing) { // playhead
            const hx = c.x + @as(i16, @intFromFloat(self.playhead / @as(f32, WAVE_LEN) * @as(f32, @floatFromInt(c.w))));
            g.blit.fill(g.fb, hx, c.y, 1, @intCast(c.h), gui.ACCENT);
        }
    }

    fn drawTransport(self: *Demo, c: Rect) void {
        const g = &self.g;
        const bw: i16 = 34;
        const y = c.y + 6;
        if (g.button(.{ .x = c.x + 4, .y = y, .w = bw, .h = 20 }, "PLAY", self.playing)) {
            self.playing = true;
            self.playhead = 0;
        }
        if (g.button(.{ .x = c.x + 4 + bw + 2, .y = y, .w = bw, .h = 20 }, "STOP", false)) {
            self.playing = false;
        }
        if (g.button(.{ .x = c.x + 4 + (bw + 2) * 2, .y = y, .w = bw, .h = 20 }, "REC", self.recording)) {
            self.recording = !self.recording;
        }
        if (g.button(.{ .x = c.x + 4 + (bw + 2) * 3, .y = y, .w = bw, .h = 20 }, "LOOP", self.looping)) {
            self.looping = !self.looping;
        }
    }
};
