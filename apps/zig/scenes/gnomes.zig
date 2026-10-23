// --------------------------------------------------------------------------
// THE GNOMES GROUP — "BB25" (Buxton Bytes 2025 Fantasy Cracktro Challenge),
// zerkman's cracktro intro, fujiology.org/ST/T/TGG/TGG_BB25.ZIP (the .ZIP's
// TGG_BB25.PRG, LSD-unpacked; every rip below is a byte-exact copy from
// /tmp work against that image, so this file notes the depacked.bin offset of
// each one).
//
// WHAT THE INTRO IS. One full-overscan screen, driven by an HBL palette
// player that rewrites two colour registers scanline by scanline out of
// raster tables inside the program. Over that:
//   * the full-screen rainbow bands (the 128-word cycling raster table),
//   * a big 16-slot cracktro logo "THE GNOMES GROUP" across the top (in the
//     original an undecoded 400-byte-glyph brick-melt font — see the blocker
//     note below; here a rebuilt logo over the intro's own small font),
//   * SpongeBob, the intro's only bitmap, right of centre (drawn once),
//   * three brick raster boxes under the logo,
//   * the cyan English message typed in one character at a time, TTY-style,
//     with CR/LF line breaks and a 250-frame pause, then wiped and repeated,
//   * the big bottom scroller, the 2885-character French thank-you text,
//   * "Custodian" (the file's own 6-subtune SNDH), music on, F1-F6 to pick a
//     subtune exactly as the on-screen message says.
//
// EXACTLY FROM THE ORIGINAL (depacked.bin offsets):
//   * sbob raw: planar sprite, params at 0x5fd8 (9 words wide = 144 px, 158
//     rows), data at 0x5ffc, row pitch 72 B, standard ST word-interleaved
//     4 planes (per 16 px: plane 0..3 words) -> chunky indices 0..15
//     (assets/sbob.raw, 144*158). The first rip shipped a mis-decoded sprite
//     (every other 16-px column lost); re-decoded 2026-10-23 from depacked.bin.
//   * SpongeBob's palette: registers 2..15, the 14 words at 0x5fe0 (code
//     $5fc4(pc) + the 0x1c header), installed by the Timer-B handler at
//     $93ac over the sprite's lines; registers 0/1 stay the per-line rasters.
//   * the 8x8 font: 256 glyphs x 1 planar byte per row at 0xe314 (assets/
//     font8.bin; the same glyph shapes the cyan TTY used: the 'A' checked)
//   * the cyan message: 0xc1a8..0xc1a7+0xbb, byte-exact incl. \r\n and the
//     trailing space; the pause semantics from the dis ($fa = 250 frames)
//   * the big scroller text: 0xb662..0xc1a7, byte-exact (with its trailing
//     space run), no CR/LF, one 0x00 terminator
//   * raster tables, big-endian words as they are in the file: the 128-word
//     rainbow at 0x9a22 (code lea $9a06 + 0x1c file offset), T1 (24 words,
//     the yellow-white-cyan→cyan-white-yellow loop) at 0x9588, T2 (16 words,
//     the red-green brick ramp) at 0x9b8e. The colour-word layout is not
//     guessed: machine/beam.zig stToRgba() is this machine's decoder for an
//     ST register word (nibbles [ignored][r][g][b], gun = ((n&7)<<1|(n>>3))levels),
//     and st() below is that formula verbatim so any word this scene puts in
//     the palette renders exactly as the machine would render it.
//   * the music is David Whittaker's "Custodian" (6 subtunes, F1-F6 = 1..6).
//     The intro embeds Grazey's 6228-byte rip; this cart plays the SNDH
//     archive's custodian.sndh instead: same periods frame for frame, but the
//     embedded rip leaves subtune 3's volumes at 0 here (see app.zig MUSIC).
//
// DELIBERATE DEPARTURES (all documented, all forced by the one blocker or by
// reuse of extracted shapes).
//   1. THE BIG FONT BLOCKER. The original's logo/big-scroll glyphs are
//      400-byte records behind a directory at 0x1446 (entry = (char-0x20)*2,
//      byte-offset from the base; uniform 0x190 stride; font spans
//      0x14bc..0x5fbc, ending on the sprite's params). The draw is a moving
//      16 px window of move.p.l halves (25 rows x stride $a0, a2/a3 two
//      byte-streams advancing $64 per frame). Six static-rip render attempts
//      (per-slice windows, plane-per-slice, 24 px rows) all produced noise or
//      sheared letters; the record's internal layout resisted decoding, so
//      THE GLYPH SHAPES ARE NOT IN THIS PORT. In their place the intro's own
//      small 8x8 font (this is the font the TTY used) is scaled 3x for the
//      logo and 4x for the band — a documented approximation of the brick
//      look, not a claim to be the original's glyphs.
//   2. Colour assignment per element is this scene's own (the original's
//      per-line player rewrote registers 0/1 across everything; the exact
//      table-to-element mapping was not recoverable): index 0 = the rainbow
//      band + the screen's background, 1 = T2 for the boxes and the big-band
//      glyphs, 2 = T1 inside the logo rows, 3 = static boot-table orange rim
//      (0x960 word 3 = the VBL ramp's own tone), 4 = static cyan (T1[15]) for
//      the TTY, 18..31 = SpongeBob's own registers 2..15 (the Timer-B swap
//      becomes a second set of entries); the sprite's colour-0 pixels are
//      transparent (the raster shows through, as colour 0 did) and its
//      colour-1 pixels take index 1, the T2 raster.
//   3. Geometry sits on this machine's 400x280 overscan plane: logo at
//      rows 12..35 spanning 16 slots of 24 px, boxes 40x26 at y 44 x
//      26/80/134, the TTY strip's 11-word / 117-row panel at y 80..191,
//      SpongeBob at (248, 84), the big band 32-px glyphs on a 40-px advance
//      rolling left 2 px a frame across rows 244..275.
//   4. The rainbow rolls one word a frame (the tables alone cannot say how
//      fast the original's player stepped its index).
//
// No floats anywhere in the frame loop: all integer/fixed work.
//
// Files: gnomes/app.zig (the frame loop), tables.zig (rasters + st()),
// text.zig (the strings), draw.zig (font, logo, boxes, sprite), testapi.zig
// (the headless harness's exports, apps/gnomes_headless.mjs).
// --------------------------------------------------------------------------
const app = @import("gnomes/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("gnomes/testapi.zig");
    }
}
