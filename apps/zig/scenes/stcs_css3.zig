// --------------------------------------------------------------------------
// ST COMPUTER SERVICE (STCS) — "DEMONIAQ", the Tsunoo Rhilty intro for the
// 3rd CSS Convention (stcs_3.prg).
//   code Tsunoo Rhilty · letter path Billy Octet · music Rob Hubbard, "Thrust"
//
// Ported from the ORIGINAL ST binary, not from a remake. The addresses in
// these files are TEXT offsets of the unpacked program (HARTMANNS EASYPACKER
// wrapper undone). A Python model of every per-frame routine reproduces Hatari
// byte for byte; this port is checked frame by frame against that model,
// borders included (apps/stcs_css3_headless.mjs).
//
// WHAT IS ON SCREEN (one plane, the ST's four bitplanes shown through the
// colour registers, stcs_css3/display.zig):
//   - the logo (lines 0..40) and the letter bitplanes of pic1;
//   - a whole-palette raster: Timer B swaps all 16 registers at 17 line
//     positions — a black strip, the grey bands, the 9 x 2-line bar that
//     ping-pongs 2 lines a frame over 96 frames with a 9-colour window
//     sliding over a 27-colour ring, and the scroller's blue chrome. Colour 0
//     changes with every band, so the bands run through the borders
//     (stcs_css3/raster.zig);
//   - two text columns scrolling up as 127-line rings, plane 0 at 1 px and
//     plane 1 at 2 px a frame; the palettes make plane 0 yellow above the bar
//     and plane 1 magenta below it (stcs_css3/columns.zig);
//   - 100 stars in plane 3, one a line (stcs_css3/machine.zig);
//   - the four STCS letters in plane 2 flying along the path tables;
//   - the 4 px/frame scroller (stcs_css3/scroller.zig). Columns + stars and
//     the scroller take turns: 300 frames, then the scroller to its next
//     pause marker.
// Start-up, as the program runs it: 24 black VBLs, the picture and the music,
// the stars released one line at a time over 709 frames (the measured busy
// loop), a warp 7 -> 1 px/frame (12 frames a step), then the main loop.
//
// SKIPPED: the ~590 black frames of the EASYPACKER depack before the program's
// entry (ZigMachine loads the cart itself).
//
// STARS: the original seeds them from XBIOS Random, TOS's LCG. The seed is
// TOS's boot state; the one that reproduces the Hatari run is used
// (machine.zig), so the stars are Hatari's too.
//
// KEYS: Space leaves, as in the original; Escape too, the repo's convention.
//
// MUSIC: Rob Hubbard, "Thrust" — the replay inside the intro is the SNDH body
// byte for byte (Hubbard_Rob/Thrust.sndh, Grazey, TC50, FLAG ~y, 1 subtune),
// requested when the picture appears, as the original starts it.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;

const Machine = @import("stcs_css3/machine.zig").Machine;
const timeline = @import("stcs_css3/timeline.zig");
const display = @import("stcs_css3/display.zig");

const MUSIC = "thrust.sndh";
const PLANE = 0;
const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = ' ';

/// One ST VBL, in microseconds: 50 Hz on any host.
const VBL_US: u64 = 20_000;
const MAX_CATCH_UP: u64 = 4;
const MAX_FRAME_US: u64 = 1_000_000;

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    m: Machine,
    clock_us: u64,
    vbls: u64, // VBLs run so far
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.m.init();
        self.clock_us = 0;
        self.vbls = 0;
        self.wants_quit = false;
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setFrameBufferHBLHandler(0, display.timerB);
        display.buildBorder(&self.m, false);
        zigos.setHBLHandler(display.borderHbl);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (std.math.isFinite(dt) and dt > 0) {
            const us: u64 = @intFromFloat(@min(@as(f64, dt) * 1000.0, @as(f64, MAX_FRAME_US)));
            self.clock_us += us;
        }
    }

    /// Show the state the border already shows (hwClear painted it from the
    /// table built last frame), THEN run the VBLs due and build the border for
    /// the state the next frame shows. One host frame of latency buys a border
    /// that is always the picture's own.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        display.present(&self.m, self.lit(), &zigos.lfbs[PLANE]);
        const due = self.clock_us / VBL_US;
        var n: u64 = 0;
        while (self.vbls < due) : (n += 1) {
            if (n == MAX_CATCH_UP) {
                self.vbls = due;
                break;
            }
            self.vbl();
        }
        display.buildBorder(&self.m, self.lit());
    }

    fn lit(self: *const Demo) bool {
        return self.vbls > timeline.PREROLL;
    }

    fn vbl(self: *Demo) void {
        self.vbls += 1;
        if (self.vbls <= timeline.PREROLL) return;
        if (self.vbls == timeline.PREROLL + 1) zg.requestSong(MUSIC);
        timeline.intro(&self.m, self.vbls - timeline.PREROLL - 1);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_SPACE or cp == K_ESC) {
            self.wants_quit = true;
            zg.stopSong();
        }
    }
};
