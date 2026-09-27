// --------------------------------------------------------------------------
// TCB SCREEN #1, "A-COUPLE-OF-BORDERS-SCREEN", from the disk: $E192 in the TCB
// load (tracks 12..37 to $8000; prototypes/snyd_re/NOTES_tcb.md). It is a
// digitised sound demo more than a picture:
//   * the sound is ONE sample byte a scanline (the HBL, $DEDA, and inline in
//     the fullscreen loop) through a volume table into YM registers 8..10: 0.69 s
//     of speech ten times, then a stream that loops from $32AD0 for ever. Here
//     it is the hand-built SNDH of that stream (swedish_newyear_tcb_digi.sndh,
//     Timer A 15754 Hz), and the sample pointer a4 is SIMULATED at its rate:
//     7877/25 = 315.08 samples a VBL (the ST plays 313 in the intro, 312 in the
//     fullscreen; measured in Hatari), so the pictures change with the sound.
//   * the picture is a fixed noise buffer (tcb1_init.zig) shown from 16
//     shuffled bases, one a VBL. Once a4 passes $2D0E1 the VBL runs a
//     fullscreen: top and side borders open (bottom closed), 230-byte lines
//     (tcb1_show.zig). Once it passes $32AD0 the TCB logo is drawn, each line on
//     the preshift the logo had some frames before (a 26-entry delay line) --
//     a wobble that ripples down it.
// Colours: the palette $E1EA (greys), colour 0 black; no rasters.
// Space (release) leaves: $E0C2 restores the machine, colour 0 = $777, and
// TCB #2's set-up runs (see the report: ~73 VBLs, noise with a light border,
// then black).
//
// The remake drew random noise and a sine-wobbled logo over a CODEF canvas,
// and played the stream as two OGG files.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const frame = @import("frame.zig");
const init_part = @import("tcb1_init.zig").init;

const Ram = st.Ram;

pub const BASE: u32 = 0x8000; // where the loader puts the TCB part
pub const TOP: u32 = 0x80000;

pub const NOISE: u32 = 0x70000; // the noise buffer, $EA62 bytes
pub const PRESHIFTS: u32 = 0x49DCC; // 12 blocks of $2D0: the logo shifted 4..15
pub const SHOWN: u32 = 0xDD30; // .l the base on show (the logo is drawn on it)
pub const LAST_DRAW: u32 = 0xDD34; // .l the end of the last logo drawn
pub const PALETTE: u32 = 0xE1EA;
const DELAY: u32 = 0xD8DA; // .l x 26: per logo line, the step to its source line
const COUNT: u32 = 0xD956; // .w 0..49
const SELECT: u32 = 0xD958; // .w 0..7
const STARTS: u32 = 0xD95A; // .w x 8: where in WOBBLE each 50 frames start
const START: u32 = 0xD96A; // .w
const WOBBLE: u32 = 0xD96C; // .w the preshift (0..11) a frame
const BASES: u32 = 0xDF5E; // .l x 16
const BASE_IX: u32 = 0xDF9E; // .l 0..60, step 4
const LOGO_ON: u32 = 0xDF5D; // .b
const LOOPS: u32 = 0xDF58; // .l
const LOOP_END: u32 = 0xEA9C; // .l
const LOOP_LEN: u32 = 0xEAA0; // .l
const LOGO_BYTES: u32 = 0x4B6C; // the logo's end from the base, in 230-byte lines
const LINE = 230; // bytes a fullscreen line
pub const STREAM: u32 = 0x1908C;
const FULLSCREEN_AFTER: u32 = 0x2D0E1;
const LOGO_AFTER: u32 = 0x32AD0;
const PER_VBL_NUM = 7877; // 15754 Hz / 50, as a fraction
const PER_VBL_DEN = 25;

pub const Tcb1 = struct {
    a4: u32, // the sample pointer (a register on the ST, not in RAM)
    frac: u32,
    shown: u32, // the base this frame shows (set by the previous VBL)
    full: bool, // this frame is a fullscreen

    /// The part's tracks are in `r`, everything above them zero.
    pub fn init(self: *Tcb1, r: *const Ram) void {
        init_part(r);
        self.* = .{ .a4 = STREAM, .frac = 0, .shown = NOISE, .full = false };
    }

    /// One VBL: the samples since the last one (and $DEF2's bookkeeping, which
    /// the main loop runs between VBLs), then $DD38.
    pub fn vbl(self: *Tcb1, r: *const Ram) void {
        self.frac += PER_VBL_NUM;
        self.a4 += self.frac / PER_VBL_DEN;
        self.frac %= PER_VBL_DEN;
        self.loop(r);
        self.shown = r.l(SHOWN);
        body(r);
        self.full = self.a4 > FULLSCREEN_AFTER;
    }

    pub fn fullscreen(self: *const Tcb1) bool {
        return self.full;
    }

    pub fn borders(self: *const Tcb1) frame.Borders {
        return if (self.full) .top_sides else .closed;
    }

    /// $DEF2: the logo from $32AD0 on; past the loop's end, back by its length
    /// (the speech loops 10 times, then the music part for ever).
    fn loop(self: *Tcb1, r: *const Ram) void {
        if (self.a4 > LOGO_AFTER) r.sb(LOGO_ON, 0xFF);
        if (self.a4 <= r.l(LOOP_END)) return;
        self.a4 -= r.l(LOOP_LEN);
        r.sl(LOOPS, r.l(LOOPS) + 1);
        if (r.l(LOOPS) >= 10) {
            r.sl(LOOP_END, 0x41234);
            r.sl(LOOP_LEN, 0xE764);
        }
        r.sw(LOGO_ON - 1, 0); // $DF5C and $DF5D
        if (self.a4 > LOGO_AFTER) r.sb(LOGO_ON, 0xFF); // the main loop, at once
    }
};

/// $DD38 without the sound: erase, delay line, draw, next base.
pub fn body(r: *const Ram) void {
    erase(r);
    delay(r);
    if (r.b(LOGO_ON) != 0) draw(r);
    const ix = (r.l(BASE_IX) + 4) & 0x3F;
    r.sl(BASE_IX, ix);
    r.sl(SHOWN, r.l(BASES + ix));
}

/// $D7D8: the last logo's box, filled back to front with 16 bytes a line of
/// the shown base's top, longs 1,2,3,1,3,4,1,3,2,4 -- pseudo-noise.
fn erase(r: *const Ram) void {
    var a1 = r.l(LAST_DRAW);
    var a0 = r.l(SHOWN);
    const order = [10]u32{ 0, 1, 2, 0, 2, 3, 0, 2, 1, 3 };
    for (0..18) |_| {
        // read first: in the intro the box is low enough to overwrite these
        const d = [4]u32{ r.l(a0), r.l(a0 + 4), r.l(a0 + 8), r.l(a0 + 12) };
        for (order) |k| {
            a1 -%= 4;
            r.sl(a1, d[k]);
        }
        a0 += 16;
        a1 -%= 0xBE;
    }
}

/// $D84A: every line's step moves one line down; line 0 takes this frame's
/// preshift, and line 1's step is corrected so it still reaches its source.
fn delay(r: *const Ram) void {
    var k: u32 = 25;
    while (k > 0) : (k -= 1) r.sl(DELAY + 4 * k, r.l(DELAY + 4 * (k - 1)));
    var cnt = r.w(COUNT) + 1;
    if (cnt >= 50) {
        cnt = 0;
        const sel = (r.w(SELECT) + 1) & 7;
        r.sw(SELECT, sel);
        r.sw(START, r.w(STARTS + 2 * @as(u32, sel)));
    }
    r.sw(COUNT, cnt);
    const shift: u32 = r.w(WOBBLE + 2 * @as(u32, cnt +% r.w(START)));
    const e0 = shift * 0x2D0 -% 0x28;
    r.sl(DELAY, e0);
    r.sl(DELAY + 4, r.l(DELAY + 4) -% e0 -% 0x28);
}

/// $D80C: 18 lines, bottom up, 40 bytes each, on the shown base.
fn draw(r: *const Ram) void {
    var a1 = r.l(SHOWN) + LOGO_BYTES;
    r.sl(LAST_DRAW, a1);
    var a0: u32 = PRESHIFTS + 0x2D0;
    for (0..18) |i| {
        a0 +%= r.l(DELAY + 4 * @as(u32, @intCast(i)));
        a1 -= 40;
        r.cp(a1, a0, 40);
        a1 -= LINE - 40;
    }
}
