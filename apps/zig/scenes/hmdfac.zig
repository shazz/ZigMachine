// --------------------------------------------------------------------------
// Hemoroids (HMD) — "Factory Cracktro" (HMDFAC.PRG), a Team Factory tribute,
// Buxton Bytes 2025 "Fantasy Cracktro Challenge"; code Ayoros, graphics
// Pandafox, music AD. fujiology.org/ST/H/HMD/HMDFAC.ZIP. An Atari STe
// cracktro (Pouet 103795 / Demozoo 369835 say STe, and it runs on Hatari
// STe: no Falcon hardware, STe 4-bit palette words; an earlier version of
// this header called it a Falcon 030 intro, wrongly).
//
// HOW IT WAS READ. The PRG is UPX 3.91 packed. It was run in Hatari (STe,
// TOS 1.62, 1 MB) through shirazmcp and read from RAM: it loads at $aa9a,
// so RAM address - $aa9a = the depacked-image offset the first port used
// (both are given below where they differ). RAM dumps and the 68000 reading
// live in prototypes/hmdfac_re/ (untracked); the original's drawn cube
// pages are pinned in apps/hmdfac_original.json.
//
// WHAT THE INTRO IS. One 320x249 art plate in a 416x276 frame, and a Timer B
// chain under all of it (rasters.zig): a LASER line at display line 2 and
// another at line 196 (colour 0 rewritten every 12 pixels from a sweeping
// gradient table), and a SPLIT palette — a top palette from line 3, a bottom
// one from line 197. Beats, in frames from the first loop VBL:
//   * 193 frames, the BOB ($b9dc): the chrome HMD logo on its own page, the
//     STe video address counter ($ff8205/07/09) set each frame to the page
//     plus a word of the $2d1ea table (192 words, multiples of 160: the logo
//     drops 32 lines and bounces), then word 0 once more. Top palette = the
//     art palette, bottom = sixteen $0011 (whatever lies below line 196 is
//     hidden),
//   * 12 frames, the FLASH ($ac6a): the chain off, art palette everywhere,
//     colour 0 $777/$eee/$666/$ddd/$555/$ccc two frames each ($fff, then
//     subi #$888 / addi #$777 three times), then 4 more grey frames while
//     band A is pasted into both pages,
//   * 498 frames, the CUBE (120 + 250 + 128, $acd2/$ad3c/$ad8a): the chain
//     back on, colour 0 $0011 again. A solid six-face frustum, flat colours
//     (cube.zig, cube_fill.zig), flown by a 360-pair queue; camera $1356
//     down to $79e by $28, hold, then up to $1b9e. Phase 2 switches the
//     bottom palette to the art palette: band A ("HAD THE PLEASURE ...")
//     appears,
//   * then PHASE 4 forever: pages cleared, the top palette $2d3ac (pal4.raw),
//     the bottom $2d36c (band_pal.raw: the teal FACTORY logo), band B pasted
//     at page row 199, ~11 frames of precalc ($1108c/$1103a), then each frame
//     $1119a: a 3D dot figure plotted into one bitplane in turn (cleared every
//     8 frames: trails), the wave scroller.
//
// THE RIPS (assets/screens/hmdfac/; RAM / depacked offset):
//   * logo.raw — the art, $2357a / $18ae0, 320x249 chunky indices,
//   * band_a.raw / band_b.raw — the two strips (page rows 194.., 199..),
//   * art_pal.raw $2d1ba / $22720, boot_pal.raw $2d38c / $228f2 (sixteen
//     $0011), pal4.raw $2d3ac / $22912, band_pal.raw $2d36c / $228d2,
//   * laser.raw — the laser gradient, 124 words at $2ee54 / $243ba,
//   * bob.raw — the opening's 192 screen offsets at $2d1ea / $22750,
//   * sine.blob $20aee / $16054, queue.raw $210ac, rows.raw $1b9d6 (the dot
//     figure's x and y), wave.raw $13af2 (the scroller's wave),
//     text.raw $13c6c / $91d2 (the 2105-char scrolltext),
//   * font_machine.bin + charmap.bin ($148e2 / $144a8; $9e48 / $9a0e): the
//     scroller's own 32x16 font and its text-byte map,
//   * "cracoucass.sndh" -> docs/music/hmd_cracoucass.sndh (md5-matched;
//     maxYMiser, timer C, YM only).
//
// THE CUBE IS THE ORIGINAL'S, PIXEL FOR PIXEL. The face list at $2348c has
// SIX faces (count word 5), each four vertex pairs and a COLOUR word (15, 2,
// 13, 14, 7, 6) that the fill expands to plane masks; the projection's first
// word is x (an earlier reading had x and y swapped, the facing test's sign
// inverted, five faces, and took the colour word for a row-stripe mask).
// The fill is reproduced down to the 68k flags (cube_fill.zig), and four
// pages the original drew match the model the harness holds this cart to.
//
// DELIBERATE DEPARTURES (all documented):
//   1. In the cube phases the machine double-buffers and restores the last
//      bounding box from the art; the port keeps one page there and restores
//      only the rows the last frame drew (CHISEL copies from cart RAM). Same
//      pixels. (Phase 4 does flip two pages, as the original does.)
//   2. The flash-to-cube handover is modelled as 12 + 4 frames; the original
//      takes 16 to 18 VBLs there (two strip copies), measured to +-2.
//   3. The bottom laser's read pointer is 39 words ahead of the top's on the
//      displayed frame (three captures and an in-frame RAM read agree; the
//      stored gap between frames is 38).
//   4. Keys: scancode $39 (SPACE) was the machine's exit and $38 its colour-0
//      pop. The port: ESC = quit, SPACE = the pop as a toggle (colour 0 $711
//      over the top border and lines 0..1, as the machine shows it until the
//      top palette load).
//
// PHASE 4 IS THE ORIGINAL'S, BYTE FOR BYTE. The port keeps the machine's two
// pages in their own PLANAR layout (on zg.mem) and runs $1119a's four steps
// on them exactly — the plane clear, the scroller's wave ring, slab feed and
// 40-column copy into plane 1, the 3201-dot plot (p4_dots.zig,
// p4_scroll.zig) — mirrors each byte that changes into that page's own half
// of the plane buffer (p4_page.zig), and shows the page by moving the plane's
// read base onto it, as the machine swapped its screen base (p4.zig).
// The dot "3D figure" is a Lissajous: x from the $1b9d6 table now, y from the
// same table i frames back, four generations in four bitplanes. The font is
// the machine's own (font_machine.bin + charmap.bin): a glyph is its left 16
// columns then its right 16, which is why the first port's decodes of it as
// 32-px rows were noise; the stand-in font is gone. Three planar pages the
// original drew (frames 0, 1, 301) are pinned in apps/hmdfac_original.json.
//
// No float in the frame loop: counters, the Q9 matrix, asr, divs semantics,
// 16-bit wraps and the fill's split 16.16 register are all integer.
//
// Files: hmdfac/app.zig (the timeline), assets.zig (the rips + st()),
// rasters.zig (the Timer B chain), cube.zig + cube_fill.zig (the frustum),
// p4.zig + p4_dots.zig + p4_scroll.zig (phase 4), testapi.zig (the
// harness's exports).
// --------------------------------------------------------------------------
const app = @import("hmdfac/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("hmdfac/testapi.zig");
    }
}
