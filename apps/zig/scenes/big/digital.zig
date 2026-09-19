// --------------------------------------------------------------------------
// THE DIGITAL SOLUTION — the B.I.G. Demo's sound-test screen, reached from the
// jukebox list entry "-=THE DIGITAL DEPARTMENT=-" (see list.zig).
//
// The artwork and the wording are TEX's; the six tunes are Mad Max's
// Best-In-Galaxy conversions. Credited, never re-attributed.
//
// The CODEF remake does not contain this screen and does not contain the list
// row that opens it, so there is no screen.js behind either. It is
// reconstructed from a capture of the real screen, and the line between what
// was MEASURED and what was RECONSTRUCTED is drawn explicitly here.
//
// ---- OBSERVED (measured from the capture, BIG_DEMO_7.gif) ----------------
//   * The picture. The capture is an EXACT 2x of 320x200 — 0 mismatched rows
//     of 200 and 0 columns of 320, pairing (0,1) — so even-sampling is
//     LOSSLESS and what is drawn here is the machine's own output, not a
//     redrawing. 15 colours, at most 12 in a row: a plain 16-colour ST low-res
//     screen with no per-line trick. Every one of those numbers is asserted by
//     tools/private_tools/digital_solution_assets.py, which refuses to convert
//     if the capture were ever resampled; the full measurements are there.
//   * The text, read off the capture: the header, "DARE TO PRESS:", the six
//     numbered entries in two columns (1-3 left, 4-6 right), the SOON COMING
//     note, and "-PRESS SPACE TO EXIT TO THE B.I.G. DEMO-". Nothing is
//     retyped as glyphs; it is the picture.
//   * The tune mapping. The six entries name exactly the five SNDH images in
//     prototypes/sndh_lf/Mad_Max/Demos/Best_In_Galaxy-Digi/, and
//     Phantom_Of_The_Asteroid.sndh really carries ##02, so PHANTOMS 1 and 2 are
//     its subtunes 1 and 2 and not two entries on one tune. All six were
//     rendered on the sealed audio machine and all six make sound (0.1395 ..
//     0.2991) — worth saying, because every one is FLAG ~ay, the flag that
//     usually means a clean load and silence.
//   * The TEXT CYCLES. Every character on the screen is one palette entry, and
//     the capture caught it at #8d12e9 — ST levels (4,0,7), which is exactly
//     cycle.raw's index 13, tile 4's colour. So the text is not "purple": it is
//     whichever of the eight the cycle is on — the SAME eight the jukebox's
//     raster bands ride (Matt, 2026-09-19).
//   * Opening the screen STARTS ACE II, in its Best_In_Galaxy-Digi version.
//   * The screen is otherwise STATIC apart from the band along the bottom,
//     which is the demo's OWN SCROLLTEXT — the same one the jukebox runs,
//     carrying on from wherever it had got to (Matt, 2026-09-19). Confirmed
//     from the capture's pixels, not taken on trust: it is exactly 16 rows
//     (= A.SCROLL_H) on a flat panel, its eight non-grey colours are FONTBG[0..7]
//     in the SAME ORDER, and its outline greys are fontOUT's ST levels 3/4/6.
//     The three measurements are set out in the converter. So this screen runs
//     big_demo's scroller, at its own y, off the one shared Screen — no second
//     scroller, no second copy of the 41,859-byte text.
//   * Space returns to the B.I.G. Demo, because the screen's own last line
//     says so. It returns to the jukebox list inside this same cart.
//
// ---- RECONSTRUCTED (flagged, not hidden) ---------------------------------
//   * WHERE THE SCROLLER HAD GOT TO at capture time. Unknowable: the visible
//     fragment does not occur anywhere in the remake's 41,351-character
//     transcription, so the remake's text may simply differ from the real
//     screen's. Those 16 rows are therefore the one part NOT asserted against
//     the capture — the harness covers them with checks of their own.
//   * The fontbg fill's PHASE at this y: drawScrollerAt anchors the diagonal to
//     the glyph's own row, as the jukebox's 0-px-verified band does, and the
//     pattern repeats every 8 px, so no still could fix which phase was used.
//   * THE COLOUR CYCLE'S RATE. It is SLOWER than the jukebox's 0.4 (Matt), and
//     the exact increment is NOT KNOWN: A.DIGITAL_CYCLE_STEP is a provisional
//     half-speed 0.2, picked because it is obviously provisional, not because
//     it was measured. To be confirmed against the real demo. One constant, so
//     confirming it is a one-line change.
//   * The colour cycle's phase OFFSET, likewise: one still is one sample of an
//     eight-step loop, so any offset fits it. It runs unshifted.
//   * Whether that cycle RESTARTS when the screen is re-entered. It carries on
//     here, as the scrolltext does.
//   * The BORDER. The jukebox runs 320x270 with its top and bottom borders
//     open and this screen is drawn into that same plane, so the 40 physical
//     rows above and below the picture are filled here — with A.PANEL, the
//     grey the jukebox uses, not the black a genuinely closed border would be.
//     Do NOT "fix" this by calling openBorders() again on the way in and out:
//     setOverscanBuffer() vramAllocs a fresh buffer every call, and vramAlloc
//     has NO bounds check against the 1 MiB pool — it would bump silently past
//     VRAM_BYTES into OFF_PFB, the physical framebuffer, and corrupt the
//     composited output every frame with nothing trapping.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const Screen = @import("screen.zig").Screen;
pub const TUNES = @import("digital_tunes.zig").TUNES;

pub const K_SPACE: u32 = 32;
const K_1: u32 = '1';

/// The screen at ST scale: 320x200 indices, one per pixel. Even-sampled from
/// the capture — lossless, the doubling being exact — with the 16 scroller rows
/// blanked to the panel grey, because the scroller draws them live.
const PICTURE = @embedFile("../../assets/screens/digital_solution/screen.raw");
/// big_demo's OWN 256-entry palette with this screen's 7 colours APPENDED past
/// its last used index. Sharing one palette is what lets the jukebox's scroller
/// keep its fontbg and outline colours while this screen is up, and means
/// nothing has to be restored on the way out.
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/digital_solution/pal.dat"));

/// Where the 320x200 sits in the jukebox's 400x280 overscan plane: the visible
/// window, i.e. the picture occupies exactly the 200 non-border lines.
const X: usize = 40;
const Y: usize = 40;
/// The scroller band: rows 179..194 of the 320x200, measured off the capture.
pub const BAND_Y: usize = 179;
/// ...the same row in Screen's content coordinates, which row() offsets by A.TOP.
const BAND_ROW: usize = Y + BAND_Y - A.TOP;
/// The converter appends this screen's 7 colours to big_demo's palette starting
/// here, its first free index.
const BASE: u8 = 124;
const COLOURS: u8 = 7;
/// The one non-grey among them: every character on the screen. Not a fixed
/// colour — see cycle(); the capture merely caught it at one phase.
const TEXT: u8 = BASE + 6;
/// "Border: all grey" (Matt, 2026-09-19) — the jukebox's own A.PANEL, which its
/// opened borders and the hardware background register already use.
const BORDER: u8 = A.PANEL;

comptime {
    if (PICTURE.len != @as(usize, zg.WIDTH) * zg.HEIGHT) @compileError("screen.raw is not 320x200");
    if (X + zg.WIDTH > A.STRIDE) @compileError("the picture runs off the plane");
    if (Y + zg.HEIGHT > zg.PHYSICAL_HEIGHT) @compileError("the picture runs off the plane");
    if (A.TOP + BAND_ROW != Y + BAND_Y) @compileError("the band is not where the capture puts it");
    if (BAND_Y + @as(usize, A.SCROLL_H) > zg.HEIGHT) @compileError("the scroller band runs off the screen");
    // The whole point of appending: 0..BASE-1 must still MEAN what they mean to
    // the jukebox, or drawScrollerAt would paint this screen's greys and BORDER
    // would not be the jukebox's panel grey.
    for (0..BASE) |i| if (palette[i].toRGBA() != A.palette[i].toRGBA())
        @compileError("pal.dat diverges from big_demo's below the appended block");
    if (A.palette[BASE].a != 0) @compileError("index BASE is not free in big_demo's palette");
    if (palette[BASE + COLOURS].a != 0) @compileError("the appended block is not 7 colours");
    if (TEXT + 1 != BASE + COLOURS) @compileError("TEXT is not the last appended colour");
    // That the text colour IS a cycle colour is a measurement across two
    // different palettes (the capture's ladder and the remake's), so it is
    // asserted where the arithmetic can be done: apps/digital_solution_band.mjs.
    // The converter guarantees the picture never uses index 0 (the transparent
    // hole); checking all 64000 bytes HERE would cost a comptime branch quota
    // on every build, so it is asserted where it is cheap — in
    // digital_solution_assets.py.
}

/// One frame: the picture, then the shared scrolltext along the bottom — in
/// go()'s own order (advance, paint, scrollerTick) so the two screens step the
/// scroller at exactly the same rate and the text carries on across the swap.
/// `screen` is the jukebox's Screen; this draws from its state, it does not
/// keep any of its own.
pub fn draw(screen: *Screen, fb: *LogicalFB) void {
    screen.advance();
    paint(fb);
    cycle(fb, screen.digitalTile()); // after paint(): paint() installs the palette
    screen.drawScrollerAt(fb, BAND_ROW);
    screen.scrollerTick();
    screen.texbgTick(); // the jukebox's bands keep running underneath
    screen.digitalTick(); // ...and this screen's own, slower text cycle
}

/// Opening the screen starts ACE II — the DIGI version from
/// Best_In_Galaxy-Digi, not the jukebox's `big/Ace_2.sndh` (Matt, 2026-09-19).
pub fn enter() void {
    zg.requestSongTune(TUNES[0].song, TUNES[0].tune);
}

/// Every character on this screen is ONE palette entry, and it cycles: the
/// capture's text is #8d12e9, ST levels (4,0,7) — exactly cycle.raw's index 13,
/// tile 4's colour. So it is not "purple", it is whichever of the eight the
/// cycle is on: the SAME eight the jukebox's bands ride, stepped by this
/// screen's own slower accumulator (A.DIGITAL_CYCLE_STEP). The colour is read
/// out of cycle.raw itself — the first pixel of tile t, which walks 9..16 —
/// rather than a table copied from it, so the two cannot drift apart.
fn cycle(fb: *LogicalFB, tile: usize) void {
    fb.setPaletteEntry(TEXT, A.palette[A.cycle[tile * A.CYCLE_H * A.CYCLE_W]]);
}

/// The still part: the picture in the 200 visible lines, the panel grey
/// everywhere the real screen's borders are closed.
fn paint(fb: *LogicalFB) void {
    // The appended block (124..130) is not in the palette big_demo's init() set,
    // so this screen installs it. Identical to the jukebox's below BASE
    // (comptime-asserted), which is why nothing has to be restored on the way out.
    fb.setPalette(palette);
    for (0..Y) |y| @memset(fb.fb[y * A.STRIDE ..][0..A.STRIDE], BORDER);
    for (0..zg.HEIGHT) |y| {
        const dst = fb.fb[(Y + y) * A.STRIDE ..][0..A.STRIDE];
        @memset(dst[0..X], BORDER);
        @memcpy(dst[X..][0..zg.WIDTH], PICTURE[y * zg.WIDTH ..][0..zg.WIDTH]);
        @memset(dst[X + zg.WIDTH ..], BORDER);
    }
    for (Y + zg.HEIGHT..zg.PHYSICAL_HEIGHT) |y| @memset(fb.fb[y * A.STRIDE ..][0..A.STRIDE], BORDER);
}

/// A key while the Digital Solution is up. True means "Space: go back".
pub fn key(cp: u32) bool {
    if (cp >= K_1 and cp < K_1 + TUNES.len) {
        const e = TUNES[cp - K_1];
        zg.requestSongTune(e.song, e.tune);
        return false;
    }
    return cp == K_SPACE; // "-PRESS SPACE TO EXIT TO THE B.I.G. DEMO-"
}
