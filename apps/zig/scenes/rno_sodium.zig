// --------------------------------------------------------------------------
// SODIUM — RNO (Rave Network Overscan), "Intro for Atari ST, 1MB", Altparty.
//   code Britelite · music Excellence in Art (XIA) · graphics Zeroic + Fragment
//
// Ported from the ORIGINAL ST binary (SODIUM.PRG, UPX-packed; the addresses in
// these files are TEXT offsets of the unpacked program), not from a remake.
// Every table, seed, increment and palette is the program's own
// (rno_sodium/assets.zig); a Python model of the disassembly reproduces the
// original's screen bytes, and this port was checked against Hatari RAM
// snapshots of the real thing (apps/rno_sodium_headless.mjs).
//
// WHAT IS ON SCREEN, part by part (C = frames since the music started):
//      1..384   PO·RNO: a 256x256 logo wobbling per line, ghosted over four
//               bitplanes by a popcount palette               (wobble.zig)
//    385..576   the eye + RNO picture on the left, a pink sine curtain on the
//               right strip                                    (curtain.zig)
//    ..1100     page 1 of the text typed over the curtain, one character a frame
//    ..1200     the text wiped, two lines a frame              (typer.zig)
//    ..1968     a textured prism turning, double-buffered      (prism.zig)
//    ..2160, ..2636, ..2736   curtain, page 2, wipe
//    ..3504     a sine distorter on the lips picture, double-buffered (distort.zig)
//    ..3696, ..4172, ..4272   curtain, page 3, wipe
//    ..4656     PO·RNO again
// After C = 4656 the original exits to the desktop. A ZigMachine screen keeps
// running, so it starts again from part 1 with the tune restarted, which is
// exactly what running the program again after its init would show.
//
// SKIPPED: the ~840 black VBLs at start-up while the original converts its
// ILBMs and builds the prism blocks. That precalc is done here in init(); the
// ILBM conversion was done once, offline, by the asset script.
//
// THE MACHINE. The effects write into two 32000-byte ST screens in the ST's
// own planar layout (rno_sodium/st.zig), plane by plane as the 68000 did, and
// the VBL counter drives them at 50 Hz off the elapsed time, whatever the
// host's refresh rate: the parts change on the counter, and the counter is
// what keeps them on the music. Each host frame shows the screen the video
// base register points at, through the current 16 ST colour registers.
//
// KEYS. The original leaves on Space. Here Escape leaves (the host's own way
// back to the menu), and Space does nothing: a scene cart has no call to quit.
//
// MUSIC: "Gritty" by Excellence In Art — the demo's own tune, as the SNDH
// archive holds it (Excellence_In_Art/Gritty.sndh, ripped by Grazey, FLAG ~y,
// one subtune, TC50). The 68000 replay drives the sealed YM.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const st = @import("rno_sodium/st.zig");
const timeline = @import("rno_sodium/timeline.zig");
const prism = @import("rno_sodium/prism.zig");

const MUSIC = "gritty.sndh";
const PLANE = 0;

/// One ST VBL, in microseconds: the counter runs at 50 Hz on any host.
const VBL_US: u64 = 20_000;
/// A stalled tab catches up at most this many VBLs a frame; beyond that the
/// lost time is dropped rather than replayed as a burst.
const MAX_CATCH_UP: u64 = 4;
/// One host frame never counts for more than this (a tab left in the background).
const MAX_FRAME_US: u64 = 1_000_000;

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    m: st.Machine,
    part: usize, // the timeline entry whose pre-steps have run
    clock_us: u64, // elapsed time the host has reported
    vbls: u64, // VBLs run so far against that clock

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.m.init();
        self.part = 0;
        self.clock_us = 0;
        self.vbls = 0;
        prism.buildBlocks(); // $1388, which the original ran before the music

        // The border is colour 0, and colour 0 is $000 in all five palettes.
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        self.restart();
    }

    /// Advance the VBL counter to the host's elapsed time.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (std.math.isFinite(dt) and dt > 0) {
            const us: u64 = @intFromFloat(@min(@as(f64, dt) * 1000.0, @as(f64, MAX_FRAME_US)));
            self.clock_us += us;
        }
        const due = self.clock_us / VBL_US;
        var n: u64 = 0;
        while (self.vbls < due) : (n += 1) {
            if (n == MAX_CATCH_UP) {
                self.vbls = due;
                break;
            }
            self.vbl();
            self.vbls += 1;
        }
    }

    /// The Shifter: whatever the base register points at, this frame.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        st.present(&self.m, &zigos.lfbs[PLANE]);
    }

    /// $038C bumps f and C, then the main loop runs the next body — entering
    /// the next part first if C has passed the current one's limit.
    fn vbl(self: *Demo) void {
        if (self.m.c >= timeline.END) self.restart();
        self.m.f +%= 1;
        self.m.c += 1;
        const i = timeline.partAt(self.m.c);
        if (i != self.part) {
            timeline.enter(&self.m, i);
            self.part = i;
        }
        timeline.body(&self.m, i);
    }

    /// Main at $000E: both counters to 0, both screens to $FF, the tune from
    /// its start, and part 1's palette.
    fn restart(self: *Demo) void {
        self.m.f = 0;
        self.m.c = 0;
        self.m.scr_a = 0;
        self.m.base = 0;
        st.fillBoth();
        timeline.enter(&self.m, 0);
        self.part = 0;
        zg.requestSong(MUSIC);
    }
};
