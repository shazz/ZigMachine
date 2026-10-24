// --------------------------------------------------------------------------
// JOCHEN HIPPEL MUSIC DEMO -- Feinbein Software & Supplex, Amiga OCS, 2 Feb
// 1990 (code, graphics, text: Fred Feinbein; music: Jochen Hippel). Ported
// from the ORIGINAL executable (amigascne's SUPPLEX-JochenHippelDemo), ripped
// statically: nothing was emulated. prototypes/hippel_musicdisk_re/NOTES.md has
// the rip; its Python model reproduces the demozoo screenshot pixel for pixel.
//
// One screen: the title, the greetings, "Press a key from 'a' to 'j'", two
// rotating copper bars, text in a scrolling copper rainbow with a grey shadow.
// Keys a..j pick ten tunes from five Hippel modules (hippel_musicdisk/tunes.zig);
// Escape leaves (the original left on the left mouse button).
//
// THE AMIGA REGISTERS, AND WHAT THEY BECAME. The copper list is rebuilt word for
// word at compile time and translated by walking it (hippel_musicdisk/
// amiga_copper.zig); Amiga beam line L is physical row L - 24, so DIWSTRT's
// line $40 is the first visible row and both bars sit in the open borders.
//   COLOR00 ($180)   34 MOVEs after WAIT $2F0F.. / $090F..: the two bars ->
//                    plane 0 (400x280 overscan, all index 0), entry 0 driven
//                    per physical row by zg.copper (one slot, flicker on every
//                    line: COLOR00 is the border too, so the bars run edge to edge)
//   COLOR01 ($182)   32 MOVEs a line after WAIT (line,$4F), lines $40..$FF ->
//                    plane 1 entries 1..32, one per MOVE column (a MOVE lasts 8
//                    pixels and lands 1 pixel before its column), driven per line
//                    by zg.LinePalette(32); lines $100..$106 keep line $FF's last
//   COLOR09 ($192)   $888, the shadow -> plane 1 entry 33, set once
//   BPLCON0 $2600 (dual playfield, 1+1 planes), BPLCON1 $0010 (PF2 one pixel
//                    right), BPL1PT = BPL2PT + $20 (one row down) -> the shadow,
//                    composed once into plane 1's indices (screen.zig)
//   DIWSTRT $4081 / DIWSTOP $07C1, DDFSTRT $48 / DDFSTOP $C0 -> 256x199 text
//                    field 32 pixels into the centred 320 window (app.zig)
//   the blitter's copy of the copper list one line up a frame ($03A6) -> the
//                    phase of the table plane 1's line palette replays
// Per-line logic: none; the two tables are filled once a 50 Hz frame.
//
// TIMING. The original runs at 50 Hz: the phase steps 5 frames out of 6 here.
// The top bar shows the PREVIOUS rotation (app.zig fillBars: the screenshot says so).
//
// PLANES. Two, so each carries one library table (zg.copper's rows cover the
// whole 280-line raster but 4 entries, zg.LinePalette's 255 entries but only the
// 200 visible rows). One plane would need a hand-written HBL calling both.
// --------------------------------------------------------------------------
const app = @import("hippel_musicdisk/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("hippel_musicdisk/testapi.zig");
    }
}
