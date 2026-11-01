// --------------------------------------------------------------------------
// MIND REWIND — Reservoir Gods, EIL party 2003 (STE, 1 MB). Code Griff and
// Pink, music Count Zero, SFX Damo, graphics Sh3 and Master.
//
// Ported from the depacked MINDWIND.TOS (fujiology), analysis in
// prototypes/mindwind_re/ANALYSIS.md (branch analysis/mindwind).
//
// The whole demo is ONE STE trick: a fullscreen kernel that, in the border
// between two lines, rewrites the video counter, HSCROLL and colour 0 from a
// 280-record line list. Every part is a way of filling that list: stripe rows
// chosen by sines (A), a picture wobbled and turned over (B), interference
// images under palette cycling (C), sliding "<<<<" bands (D, the rewind), a
// 48-row hardware-scrolled scroller, chrome bars. Then the demo rewinds and
// plays itself backwards: reversed samples, the scroller right to left, VHS
// lines, the parts in reverse order.
//
// Here the list is the plane's copper list (HW 1.10.0's LBASE: the line's
// source address, mindwind/lines.zig), on ONE overscan plane; colour 0 a line
// is a real raster (copper PAL 0); the start-up buffers are generated with the
// demo's own integer code (stripes_gen, rainbow_gen, checked byte for byte by
// gen_test.zig); the music is the demo's own sequencer as an STE-DMA SNDH.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const data = @import("mindwind/data.zig");
const lines = @import("mindwind/lines.zig");
const vram = @import("mindwind/vram.zig");
const overlay = @import("mindwind/overlay.zig");
const rainbow = @import("mindwind/rainbow_fx.zig");
const scroller = @import("mindwind/scroller.zig");
const runner = @import("mindwind/runner.zig");
const endscreen = @import("mindwind/endscreen.zig");

const PLANE = 0;

pub const Demo = struct {
    ended: bool,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        self.ended = false;
        zg.requestSong(runner.MUSIC);
        const fb = &zigos.lfbs[PLANE];
        fb.setOverscanBuffer();
        fb.is_enabled = true;
        vram.init(zigos);
        if (!lines.install(fb)) @panic("mindwind: no copper list (VRAM full)");
        lines.fill(0, lines.ROWS, vram.blank, 0);
        rainbow.init();
        scroller.init();
        const sp = data.palette(data.pal_scroller);
        for (0..16) |i| fb.palette[16 + i] = lines.ste(sp[i]);
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.ended) return endscreen.tick();
        runner.tick();
        // the VBL ($516): scroller, the palette hook, the VHS lines; then the Timer A tail's fader
        scroller.step();
        if (runner.slide_row) |r| { // $BB2A: the two records' addresses only
            lines.table[r - 1].src = vram.blank;
            lines.table[r].src = vram.blank;
        }
        if (runner.hook) rainbow.cycle();
        overlay.vhs();
        overlay.fadeTick();
        if (runner.ended) {
            self.ended = true;
            endscreen.start();
            endscreen.tick();
        }
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const field: [16]u16 = if (self.ended) endscreen.pal else switch (runner.mode) {
            .fader => overlay.pal,
            .rainbow => rainbow.pal,
            .band => data.palette(data.band_pal),
        };
        for (1..16) |i| fb.palette[i] = lines.ste(field[i]);
        lines.build();
    }
};
