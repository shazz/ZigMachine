// --------------------------------------------------------------------------
// RNO (Rave Network Overscan) — NATRIUM, 96k intro for Atari ST, 1 MB, 8 MHz.
//   code Britelite · music 505 ("Triplex") · graphics Bracket, Britelite, Fragment
//
// Ported from the ORIGINAL ST binary (NATRIUM.PRG, UPX-packed; addresses are
// the unpacked program's, loaded at $AA9A). Every effect was reverse-engineered
// into a bit-exact Python model checked against Hatari RAM snapshots, and the
// Zig here is those models' integer math; apps/zig/scenes/rno_natrium/
// verify_test.zig checks the port against them and against the snapshots.
//
// 153.6 s on one global VBL counter ($144AC), part by part:
//   $0C0  plane-0 dot tunnel under plane-1 curtains, RNO then NATRIUM revealed
//         row by row, erased, curtains closed          (tunnel_dots.zig)
//   $600  chunky box beside a doubled crop of the grey girl: tunnel, then the
//         face wobble                                   (chunky_box.zig, decor.zig)
//   $C00  env-mapped chamfered cube over the grey girl (envmap.zig, envfill.zig)
//   $F00  the reclining girl and three credit rows, white blinds (credits.zig)
//   $1200 the chrome twister and the greetings         (twister.zig)
//   $1800 env-mapped pentagonal prism over the red-scarf girl
//   $1B00 rotozoom box beside a crop of the red-scarf girl
// joined by vertical zoom transitions (transitions.zig), all sequenced by
// timeline.zig / parts_a.zig / parts_b.zig exactly as the 68000 program is.
//
// ONE PLANE. The ST screen is kept as the ST had it -- two 32000-byte
// interleaved-bitplane buffers the effects write word for word -- and the shown
// one is expanded to palette indices each frame (st.zig). No rasters: the
// intro installs only a VBL. It quits to the desktop at $1E00; here it starts
// over, music and all. Space quit the original; Escape leaves here, as on
// every screen.
//
// MUSIC: "Triplex" by 505, the SNDH ripped out of NATRIUM.PRG itself (the VBL
// calls its play vector at $564DA; init $564D2, exit $564D6), 36,424 bytes,
// verified on the sealed YM (apps/sndh_headless.mjs: mode 4, peak 0.56). The
// archive's prototypes/sndh_lf/505/Triplex.sndh is a DIFFERENT build flagged
// ~a (STE DMA), which this machine plays as silence, so the intro's own copy
// ships instead.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const st = @import("rno_natrium/st.zig");
const timeline = @import("rno_natrium/timeline.zig");

const MUSIC = "rno_natrium.sndh";
const PLANE = 0;
/// The ST's VBL is 50 Hz; the host's frame is whatever the display runs at.
/// The timeline is music-synced, so it advances by real 20 ms VBLs.
const VBL_US: u32 = 20_000;
const MAX_VBLS_PER_FRAME: u32 = 3; // after a stall, catch up a little, not all of it

pub const Demo = struct {
    seq: timeline.Seq,
    vbl_us: u32, // microseconds towards the next VBL

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.vbl_us = 0;
        self.seq.reset();
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.clearFrameBuffer(0);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 }); // colour 0 is $000 throughout
        zg.requestSong(MUSIC);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        const ms = if (dt > 0 and dt < 1000) dt else 0;
        self.vbl_us += @intFromFloat(ms * 1000);
        var n: u32 = 0;
        while (self.vbl_us >= VBL_US) : (self.vbl_us -= VBL_US) {
            if (n < MAX_VBLS_PER_FRAME) self.seq.tick();
            n += 1;
            if (self.seq.finished) {
                self.seq.reset(); // $1E00: from the top, music restarted
                zg.requestSong(MUSIC);
            }
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        for (self.seq.pal, 0..) |c, i| fb.palette[i] = st.stColor(c);
        st.toChunky(self.seq.shownBuf(), fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h], fb.stride);
    }
};
