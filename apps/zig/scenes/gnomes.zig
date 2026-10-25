// --------------------------------------------------------------------------
// THE GNOMES GROUP — "Fantasy Cracktro" (Buxton Bytes 2025 Fantasy Cracktro
// Challenge, 2025-03-15, Atari ST, code + graphics zerkman), from the original
// fujiology.org/ST/T/TGG/TGG_BB25.ZIP (TGG_BB25.TOS). Pouet 103811, Demozoo 370011.
//
// HOW IT WAS PORTED. The intro was run in Hatari (shirazmcp, TOS 1.62, STF, 1 MB)
// and dumped from RAM while running; every asset and table is ripped from that
// dump by tools/private_tools/gnomes_rip.py, and every behaviour below is read
// off the disassembly of the running code (RAM addresses; the program's TEXT is
// at $AA9A). The harness (apps/gnomes_headless.mjs) holds the cart to a model of
// that code AND to Hatari screenshots of the original at known frames.
//
// WHAT THE SCREEN IS. A 320x276 screen (top and bottom borders open, sides
// closed), double-buffered, two colour registers rewritten at every line end
// from a 276-line list by Timer B, and three palette splits:
//   * the background: colour 0 per line = a 512-word hue table rolled one word a
//     frame, under 16 copper bars of 15 lines on a sine (rasters.zig);
//   * colour 1 per line, static: the logo fill ramp, the VU ramp, a 128-word hue
//     wheel under the text, the tag ramp and the scroller fill;
//   * "THE GNOMES GROUP", a 288x36 Degas Elite logo (regs 2..7 a gold ramp,
//     colour 1 its fill), each line re-copied every frame at x = 16 + a word of a
//     2816-word table indexed by frame + line: the sway and the shear (logo.zig);
//   * three VU meters on the YM's three volumes (vu.zig);
//   * 13 pages typed one character a frame in the 8x8 font (tty.zig);
//   * SpongeBob (144x158, his own regs 2..15 from line ~50);
//   * the 2885-char French scroller in a 32x25 font, 8 px a frame (scroller.zig);
//   * "Custodian" (David Whittaker, Grazey's 6-subtune rip), F1-F6 pick a subtune.
//
// PLANES: ONE overscan plane (400x280) carries all of it. The ST screen sits at
// plane x 40..359 (the side borders show colour 0 only, as on the ST: index 0 is
// the background there), ST line L at plane row L + 2.
//
// RASTERS (real ones): colour 0 and colour 1 are copper slots on entries 0 and 1,
// one value per physical row, FLICK on every row so all four borders are open.
// The three palette splits of regs 2..7 become three static entry ranges (logo
// 2..7, SpongeBob 18..23, scroller 34..39): every pixel is drawn once in the
// range its line has on the ST, so nothing changes mid-frame but colours 0/1.
//
// DEPARTURES (documented, each measured or bounded by the harness):
//   1. On the ST colour 0 changes a few pixels into the NEXT line's left border
//      (Timer-B latency, jitter 0..~45 px); here it changes at the line start.
//   2. The $13EAA handler pokes colour 1 = $700 for the rest of the
//      bottom-border line; nothing there uses colour 1.
//   3. Frame 1's raster list is the original's unwritten (black) buffer.
// No float anywhere in the frame loop.
// --------------------------------------------------------------------------
const app = @import("gnomes/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("gnomes/testapi.zig");
    }
}
