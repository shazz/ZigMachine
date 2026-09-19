// --------------------------------------------------------------------------
// THE DIGITAL SOLUTION — the B.I.G. Demo's sound-test screen, reached from the
// jukebox list entry "-:THE DIGITAL DEPARTMENT:-" (see list.zig).
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
//   * The picture. The capture is 640x400 and an EXACT 2x doubling of
//     320x200: row 2k == row 2k+1 and col 2k == col 2k+1, pairing (0,1), with
//     0 mismatched rows of 200 and 0 mismatched columns of 320. (Pairing
//     (1,2) mismatches 151 rows and 317 columns — which is how we know (0,1)
//     is the true one.) So even-sampling to 320x200 is LOSSLESS, and what is
//     drawn here is the machine's own output, not a redrawing.
//   * 15 distinct colours in the whole frame, at most 12 in any one row: a
//     plain 16-colour ST low-res screen, 320x200, NO per-line palette trick.
//     tools/private_tools/digital_solution_assets.py asserts all of that and
//     refuses to convert if the capture were ever resampled.
//   * The text, read off the capture: the header, "DARE TO PRESS:", the six
//     numbered entries in two columns (1-3 left, 4-6 right), the SOON COMING
//     note, and "-PRESS SPACE TO EXIT TO THE B.I.G. DEMO-". Nothing is
//     retyped as glyphs; it is the picture.
//   * The tune mapping. The six entries name exactly the five SNDH images in
//     prototypes/sndh_lf/Mad_Max/Demos/Best_In_Galaxy-Digi/, and
//     Phantom_Of_The_Asteroid.sndh really carries ##02 — two subtunes — so
//     PHANTOMS 1 and PHANTOMS 2 are subtunes 1 and 2 of one image and not two
//     entries pointed at the same music. All six were rendered on the sealed
//     audio machine and all six make sound (peaks 0.1395 .. 0.2991), which is
//     worth saying because every one of them is FLAG ~ay — the flag that
//     usually means a clean load and silence.
//   * The screen is STATIC apart from the band along the bottom, which is the
//     demo's OWN SCROLLTEXT — the same one the jukebox runs, carrying on from
//     wherever it had got to (Matt, 2026-09-19). Confirmed from the capture's
//     pixels, not taken on trust:
//       - rows 176..178 and 195..199 are ONE colour (#ababab) across all 320
//         columns and rows 179..194 are the only ones that are not, so the band
//         is exactly 16 rows on a flat panel — and 16 is A.SCROLL_H.
//       - the band's eight non-grey colours are big_demo's FONTBG[0..7] in the
//         SAME ORDER (orange, light blue, blue, teal, dark teal, dark red, red,
//         tan), each within one ST level, two of the eight exact.
//       - its glyph outline greys are ST levels 3/4/6, which are exactly
//         fontOUT's 0x63/0x82/0xc1.
//     So this screen runs big_demo's scroller, at its own y, off the one shared
//     Screen — no second scroller, no second copy of the 41,859-byte text.
//   * Space returns to the B.I.G. Demo, because the screen's own last line
//     says so. It returns to the jukebox list inside this same cart.
//
// ---- RECONSTRUCTED (flagged, not hidden) ---------------------------------
//   * WHERE THE SCROLLER HAD GOT TO at capture time. Unknowable, and not worth
//     guessing: the visible fragment does not occur anywhere in the remake's
//     41,351-character transcription at all, so the remake's text may simply
//     differ from the real screen's. The band is therefore the only part of
//     this screen that is NOT asserted against the capture — see the harness,
//     which covers those 16 rows with checks of its own instead.
//   * The fontbg fill's PHASE at this y. drawScrollerAt anchors the diagonal to
//     the glyph's own row, as the jukebox's 0-px-verified band does. The
//     pattern repeats every 8 px, so no capture of a static screen could fix
//     which phase the real screen used.
//   * Whether the jukebox's OTHER animations keep running underneath. The
//     scroller is visible here, so it must; the colour bands are not visible,
//     so texbg is left alone while this screen is up. Unobservable either way.
//   * The BORDER. The jukebox runs 320x270 with the top and bottom borders
//     open, and this screen is drawn into that same plane. The real Digital
//     Solution is a plain 200-line screen, i.e. its borders are CLOSED, which
//     is black — so the 40 physical rows above and below the picture are
//     filled with BLACK. Visually that is a closed border; it is not one.
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

pub const K_SPACE: u32 = 32;
const K_1: u32 = '1';

/// The screen at ST scale: 320x200 indices, one per pixel. Even-sampled from
/// the capture — lossless, the doubling being exact — with the 16 scroller rows
/// blanked to the panel grey, because the scroller draws them live.
const PICTURE = @embedFile("../../assets/screens/digital_solution/screen.raw");
/// big_demo's OWN 256-entry palette with this screen's 7 colours and a black
/// border APPENDED past its last used index. Sharing one palette is what lets
/// the jukebox's scroller keep its fontbg and outline colours while this screen
/// is up, and means nothing has to be restored on the way out.
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/digital_solution/pal.dat"));

/// Where the 320x200 sits in the jukebox's 400x280 overscan plane: the visible
/// window, i.e. the picture occupies exactly the 200 non-border lines.
const X: usize = 40;
const Y: usize = 40;
/// The scroller band: rows 179..194 of the 320x200, measured off the capture.
pub const BAND_Y: usize = 179;
/// ...the same row in Screen's content coordinates, which row() offsets by A.TOP.
const BAND_ROW: usize = Y + BAND_Y - A.TOP;
/// The converter appends this screen's colours to big_demo's palette starting
/// here — its first free index — and the black border is the last of them.
const BASE: u8 = 124;
const BORDER: u8 = BASE + 7;

/// "DARE TO PRESS:" — the six entries as the picture prints them, and the Mad
/// Max SNDH each one plays. `label` is not drawn (the picture already carries
/// it); it is here so the mapping can be read, checked and reported by name.
pub const Entry = struct {
    label: []const u8,
    song: []const u8,
    tune: u8, // SNDH subtune, counting from 1
};

pub const TUNES = [6]Entry{
    .{ .label = "1. ACE II", .song = "digital/Ace_2.sndh", .tune = 1 },
    .{ .label = "2. LABELLO", .song = "digital/Labello.sndh", .tune = 1 },
    .{ .label = "3. PHANTOMS 1", .song = "digital/Phantom_Of_The_Asteroid.sndh", .tune = 1 },
    .{ .label = "4. PHANTOMS 2", .song = "digital/Phantom_Of_The_Asteroid.sndh", .tune = 2 },
    .{ .label = "5. SANXION-LOADER", .song = "digital/Sanxion.sndh", .tune = 1 },
    .{ .label = "6. STAR PAWS", .song = "digital/Starpaws.sndh", .tune = 1 },
};

comptime {
    if (PICTURE.len != @as(usize, zg.WIDTH) * zg.HEIGHT) @compileError("screen.raw is not 320x200");
    if (X + zg.WIDTH > A.STRIDE) @compileError("the picture runs off the plane");
    if (Y + zg.HEIGHT > zg.PHYSICAL_HEIGHT) @compileError("the picture runs off the plane");
    if (A.TOP + BAND_ROW != Y + BAND_Y) @compileError("the band is not where the capture puts it");
    if (BAND_Y + @as(usize, A.SCROLL_H) > zg.HEIGHT) @compileError("the scroller band runs off the screen");
    // The whole point of appending: 0..BORDER-1 must still MEAN what they mean
    // to the jukebox, or drawScrollerAt would paint this screen's greys.
    for (0..BASE) |i| if (palette[i].toRGBA() != A.palette[i].toRGBA())
        @compileError("pal.dat diverges from big_demo's below the appended block");
    if (A.palette[BASE].a != 0) @compileError("index BASE is not free in big_demo's palette");
    if (palette[BORDER].toRGBA() != (zg.Color{ .r = 0, .g = 0, .b = 0, .a = 255 }).toRGBA())
        @compileError("the appended border is not black");
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
    screen.drawScrollerAt(fb, BAND_ROW);
    screen.scrollerTick();
}

/// The still part: black where the real screen's borders are closed, the
/// captured picture in the 200 visible lines.
fn paint(fb: *LogicalFB) void {
    fb.setPalette(palette); // identical to the jukebox's below BORDER (asserted above)
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
