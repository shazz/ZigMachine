// --------------------------------------------------------------------------
// HMD — "HMDFAC" (Team Factory tribute), fujiology.org/ST/H/HMD/HMDFAC.ZIP
// (a Falcon 030 intro; the ZIP's PRG unpacked to /tmp work as
// HMDFAC_DEPACKED.PRG — every rip below is a byte-exact copy from that
// depacked image and the offsets in this file are its own offsets; note
// stutils.load strips the PRG's 28-byte header, so they are also the
// offsets used by /tmp/opencode/hmdfac/genassets.py, the certified model
// this file mirrors line for line. The model's 498 cube frames and its
// scroller frames were the eyeball gate; its div stats over the whole arc:
// 0 overflows, 0 divides-by-zero, camera $1356 → $79e → $1b9e.)
//
// WHAT THE INTRO IS. One 320x249 art plate inside full overscan, five beats:
//   * 200 dark frames: the chrome HMD logo is already in screen memory,
//     hidden by a flat boot palette of sixteen $0011 (the machine
//     pre-painted its double-buffered pages during the loading look),
//   * a 12-frame color0 flash: the plate's own 16 registers come up, then
//     color0 ramps 777/EEE/666/DDD/555/CCC, two frames per word (the code
//     writes #$fff once, then subi #888 / addi #777 re-entered by the dbra
//     at $1d0 — so $fff itself never shows, and the ramp's last word, $ccc,
//     is what the art's zero pixels keep showing through the cube phases),
//   * three cube phases (120 + 250 + 128 = 498 frames): a five-face
//     frustum, each face a $58fa triangle fill under a stripe word, in
//     exact 68k word math — a 9-word Q9 rotation matrix, asr #9 products,
//     divs.w with the overflow-keeps-dividend rule, add.w 16-bit wraps.
//     The camera walks $1356 → $79e (steps of −$28 while not $79e), holds,
//     then walks back up +$28 a frame to $1b9e,
//   * then phase 4, forever: both pages cleared to color0 once ($346),
//     PAL4 installed, the band-B thanks strip pasted at page rows
//     199..249 ($7c60 = 199 rows x 160 B rows), and a 2105-character text
//     rolls by in a 9-glyph wave over rows 3..196: y = rows[(t+i)%5040] +
//     ((wave[(t+i)%189]-100)>>1), x = i*40 − 4*(t%10).
//
// EXACTLY FROM THE ORIGINAL (depacked.bin offsets), assets/screens/hmdfac/:
//   * logo.raw   — the art, $18ae0..$22680, 4bpp nibbles -> 320x249 chunky
//     palette indices (its zeros are background = color0),
//   * band_a.raw — the thanks strip, page rows 194..239 ($7940 = 194 x
//     160 B rows), 320x46, pasted opaque,
//   * band_b.raw — the phase-4 strip, page rows 199..249 ($7c60 = 199 x
//     160 B rows), 320x51, pasted opaque,
//   * sine.blob  — the 720-word wheel at $16054: cos 0..359 then sin
//     360..719, here as little-endian words (the machine's counters are
//     byte addresses, so the wheel word index = counter >> 1),
//   * queue.raw  — the 360 (sy, sx) addend pairs at $16612, LE,
//   * rows.raw   — the 5040-word walk table at $10f3c, LE,
//   * wave.raw   — the 189-word wave at $9058, LE,
//   * boot_pal.raw / art_pal.raw / pal4.raw — 32-byte rips of the palettes
//     at $228f2 / $22720 / $22912, sixteen little-endian register words
//     each; st() below is machine/beam.zig stToRgba verbatim, so any word
//     this scene writes renders exactly as the machine would render it,
//   * text.raw   — the 2105-char scrolltext at $91d2 (ASCII, one 0xFF end),
//   * font_machine.bin — the machine's OWN font, 50 glyphs x 64 B at $9e48
//     (plus its charmap, 256 B at $9a0e, as charmap.bin). RIPPED AND SHIPPED
//     FOR PROVENANCE, NOT RENDERED — see the blocker below. They stay in the
//     assets directory but the cart does not @embedFile them (dead bytes).
//   * "cracoucass.sndh" -> docs/music/hmd_cracoucass.sndh (md5-matched
//     copy; subtune 1 at init).
//
// THE FONT BLOCKER. Phase-4 glyphs are drawn by a live preshift/slab
// machine ($63ae): slot cells $54 apart, runtime OR-smears into $aac8 of
// scratch, move.b strips at $a0 row pitch. Eight static decodes of the
// 64-byte glyph records (rows/columns, bit order, halves) produced noise;
// several letters even share identical leading words, so the stored bytes
// are the machinery's INPUT, not its display form — and the port's
// emulator step is permanently skipped (no TOS ROM in this environment),
// so no capture of the real display exists to pin the mapping down. So
// THIS SCENE RENDERS A REBUILT 32x16 MONOCHROME FONT (font.bin: ASCII
// 0x20..0x5F, 64 glyphs, row-major 1 bpp, glyph = char - 0x20) on the
// original's 40 px advance — the same stand-in the certified sim frames
// rendered. The letter shapes are a documented approximation, not the
// original's glyphs (same pattern as the gnomes cart's big-font note).
//
// DELIBERATE DEPARTURES (all documented):
//   1. color0 story = the machine's literal flow: $0011 flat through the
//      boot, the flash ramp two frames per word, then $ccc standing
//      through ALL cube phases (on the Falcon the art's zero pixels really
//      are light grey there), then PAL4 with #$11 rewritten every phase-4
//      frame ($3e8). (An earlier session modelled $0011 through the cube;
//      the $1d0 dbra re-entry proved the $ccc reading.)
//   2. $5444 — the machine's per-frame undo of the previous frame's cube
//      overdraw — becomes a per-frame re-blit of the art; phase 4 (whose
//      $6710 machinery this replaces wholesale) becomes a per-frame full
//      redraw: clear, band, text. Both render what the sim frames render.
//   3. Face-edge x intersections use integer @divTrunc where the sim used
//      float + trunc: crossings can land ±1 px. Invisible on 3-of-4
//      row striping.
//   4. Keys: scancode $39 (SPACE) was the machine's EXIT and $38 its
//      color0 pop (move.b #$7, $ff8240 = $0711 over $0011, one frame per
//      poll — the machine's own loop re-arms #$11 the next frame). The
//      port keeps both effects under the harness keys: ESC = quit (the
//      machine's $4b0 vector route), SPACE = the pop as a toggle.
//   5. The wave scroller's per-column timing is the certified model —
//      y = rows[(t+i)%5040] + wave shift, clamped >= -2 — a simplification
//      of the $62cc 45-slot delay ring; the sim's test frames were the
//      eyeball reference.
//
// No floats anywhere in the frame loop: counters, the Q9 matrix, asr
// shifts, divs semantics, wrap adds — all integer, matching the machine's
// registers word for word.
//
// BOARD COST (same pixels as re-blitting everything, which the harness pins
// against its own model of the full redraw): the palette is written only when
// the register story changes; the cube restores only the rows its last frame
// drew on (CHISEL copies from cart RAM); phase 4 clears the plane and pastes
// band B once, then each frame erases only the nine glyph boxes it drew last
// frame. Glyphs and faces are drawn as runs, never pixel by pixel.
//
// Files: hmdfac/app.zig (the timeline), assets.zig (the rips + st()),
// cube.zig (the 68k projection and the striped face fill), scroll.zig (the
// phase-4 wave scroller), testapi.zig (apps/hmdfac_headless.mjs's exports).
// --------------------------------------------------------------------------
const app = @import("hmdfac/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("hmdfac/testapi.zig");
    }
}
