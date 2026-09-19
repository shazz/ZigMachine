// The B.I.G. Demo (CODEF screen 23) — assets and the numbers behind them.
//
// Every PNG in the remake is an exact 2x doubling (row 2k == row 2k+1, column
// 2k == col 2k+1, checked for all five), and the main canvas is 640x540, so the
// screen is a 320x270 ST fullscreen: 200 visible lines with the TOP and BOTTOM
// borders open. tools/private_tools/big_demo_assets.py halves everything by
// even-sampling (lossless, given the doubling) and builds the one shared
// 256-colour palette this single plane runs on.
//
// Every geometry constant below is the original's own number, halved.

const zg = @import("zigos");

// ---- the plane ----------------------------------------------------------
pub const W: u16 = 320; // mycanvas 640 / 2
pub const H: u16 = 270; // mycanvas 540 / 2
pub const STRIDE: u16 = 400; // zg.PHYSICAL_WIDTH: the overscan plane
pub const LEFT: u16 = 40; // side borders stay CLOSED; content fills the 320
pub const TOP: u16 = 5; // 270 rows centred in the 280 physical ones

// ---- layout (screen.js go(), all coordinates halved) --------------------
/// cycler[n].draw(mycanvas, 0, 498 / 378 / 104) — three 40-row colour bands.
pub const BAND_Y = [3]u16{ 249, 189, 52 };
pub const BAND_H: u16 = 20;
/// mycanvasscr.draw(mycanvas,0,443) and myscrolltextOUT.draw(443). 443 is odd,
/// so the halved screen samples the scroller's ODD rows — which, the art being
/// a true 2x, are the same 16 rows as the even ones.
pub const SCROLL_Y: u16 = 222;
pub const SCROLL_H: u16 = 16;
/// shadow.draw(mycanvas,0,447,0.5) and (...,500,0.5): 12 rows, 2 tones.
pub const SHADOW_Y = [2]u16{ 224, 250 };
/// shadow.png's 6 halved rows: 66,37,37,37,37,66 -> which LUT each one uses.
pub const SHADOW_TONE = [6]u8{ 1, 0, 0, 0, 0, 1 };
/// mylistN.draw(mycanvas, 34, 184+16*k): five 35-char rows of the 8x8 list font.
pub const LIST_X: u16 = 17;
pub const LIST_Y: u16 = 92;
pub const LIST_STEP: u16 = 8;
pub const LIST_COLS: usize = 35;
/// mycanvas.line(0,215,640,215,2,..) and (0,231,...): two 1-row rules.
pub const RULE_Y = [2]u16{ 107, 115 };

// ---- the scroller (scrolltext_horizontal, kept in the original's 2x units)
/// wide = ceil(640/64)+1 = 11, and the loop runs i <= wide.
pub const LETTERS: usize = 12;
pub const FONT_W2: i32 = 64; // 2x tile width
pub const RING: i32 = 11 * FONT_W2; // wide*fontw: where a wrapped letter lands
pub const SPEED2: i32 = 4; // scrolltext.init(..., 4)
pub const FIRST_CHAR: u8 = 32; // initTile(64,32,32)
pub const GLYPHS: usize = 70; // 640/64 x 224/32
pub const GW: usize = 32; // halved tile
pub const GH: usize = 16;
pub const PW: usize = 8; // fontp.initTile(16,16,32), halved
pub const PH: usize = 8;
pub const P_GLYPHS: usize = 64;

// ---- palette indices, as laid out by big_demo_assets.py -----------------
pub const TRANSPARENT: u8 = 0;
pub const BLACK: u8 = 1;
/// rgb(160,160,160), the screen's own grey. The TOP row of both main.png and
/// wait.png is this colour across all 640 px, so the opened top/bottom borders
/// and the side margins must be it too — otherwise there is a visible seam
/// where the border meets the screen. It was BLACK, and the seam showed
/// (Matt, 2026-09-19).
pub const PANEL: u8 = 6;
/// mycycle.initTile(64,10,0) cuts cycle.png into 8 tiles of 64x10 — halved,
/// 32x5. Each is the same 8-colour rainbow at three stripe widths (1px on rows
/// 0 and 4, 2px on 1 and 3, 4px on row 2), rotated one colour along per tile,
/// and go() tiles it 10 across and 4 down to fill a band.
pub const CYCLE_TILES: usize = 8;
pub const CYCLE_W: usize = 32;
pub const CYCLE_H: usize = 5;
/// fontbg.png: 2px-wide stripes on a 45-degree diagonal, 8 colours, period 16.
pub const FONTBG = [8]u8{ 17, 18, 19, 20, 21, 22, 23, 24 };
/// mylist1..5.fill('#00FF00','#0033FF','#ff0000','#0033FF','#00FF00').
pub const LIST_INK = [5]u8{ 25, 26, 27, 26, 25 };
/// fontp.png's own ink — seen only on the highlighted (playing) row.
pub const FONTP_INK: u8 = 8;
/// fade[]: 30 greys, #FFFFFF down to #000000 and back up.
pub const FADE = [30]u8{ 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 1, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29 };

/// go()'s frame counter now drives only the rule fade, floor(0.5f)%30, which
/// repeats every 60 frames — 0.5 is exact in binary, so the integer count is
/// that sequence forever, and keeping it modulo 60 stops the u32 silently
/// wrapping mid-cycle after ~414 days of uptime.
///
/// The band tile does NOT ride on this: 0.4 is not exact, go()'s running sum
/// drifts below the integers, and a repeating counter cannot reproduce it.
/// Screen.texbg is a real f64 accumulator for exactly that reason.
pub const FRAME_CYCLE: u32 = 60;

/// go()'s `texbg += 0.4`: the rate the three raster bands step through
/// cycle.png's 8 tiles. Named here so it sits beside the Digital Department's
/// own rate below — they are the SAME cycle at two different speeds.
pub const CYCLE_STEP: f64 = 0.4;

/// The Digital Solution's text cycles through the same 8 colours but SLOWER
/// than the jukebox's bands (Matt, 2026-09-19).
///
/// THE EXACT INCREMENT IS NOT KNOWN. 0.2 is a provisional half-speed, chosen
/// because it is obviously provisional and not because it was measured; it is
/// to be confirmed against the real demo (eyeballed, or read out of the 68000
/// code by a session running it in an emulator). It is one constant on purpose:
/// when the real rate turns up this line is the whole change.
pub const DIGITAL_CYCLE_STEP: f64 = 0.2;

// ---- the files ----------------------------------------------------------
pub const cycle = @embedFile("../../assets/screens/big_demo/cycle.raw"); // 8 tiles of 32x5, tile-major
pub const main_img = @embedFile("../../assets/screens/big_demo/main.raw"); // 320x270, 0 = hole
pub const wait_img = @embedFile("../../assets/screens/big_demo/wait.raw"); // 320x270, opaque
pub const fontin = @embedFile("../../assets/screens/big_demo/fontin.raw"); // 70 x 32x16 MASK
pub const fontout = @embedFile("../../assets/screens/big_demo/fontout.raw"); // 70 x 32x16 indices
pub const fontp = @embedFile("../../assets/screens/big_demo/fontp.raw"); // 64 x 8x8 MASK
pub const shadow_lut = @embedFile("../../assets/screens/big_demo/shadow.dat"); // 2 x 256
pub const scrolltext = @embedFile("../../assets/screens/big_demo/scrolltext.txt"); // 41859 bytes
/// One shared 256-colour palette: main/wait greys, the 8 cycle colours, the 8
/// fontbg stripes, the outline greys, the three list colours, fade[]'s 16 greys,
/// and the 50%-shadow blends of all of them.
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/big_demo/pal.dat"));

// Every blit below goes through LogicalFB.fb, a [*]u8 with NO bounds checking,
// so a stray row scribbles over the video region and dies somewhere unrelated.
// std.debug.assert is a no-op in ReleaseSmall, so the geometry and the asset
// sizes are checked HERE instead, at comptime, for free.
comptime {
    if (STRIDE != zg.PHYSICAL_WIDTH) @compileError("STRIDE must be the overscan plane's stride");
    if (2 * LEFT + W != zg.PHYSICAL_WIDTH) @compileError("the 320 content columns are not centred");
    if (2 * TOP + H != zg.PHYSICAL_HEIGHT) @compileError("the 270 content rows are not centred");

    // The lowest row and rightmost column each layer touches.
    for (BAND_Y) |by| if (by + BAND_H > H) @compileError("a colour band runs off the screen");
    if (W % CYCLE_W != 0) @compileError("the cycle tile does not divide the screen width");
    if (BAND_H % CYCLE_H != 0) @compileError("the cycle tile does not divide a band's height");
    if (SCROLL_Y + SCROLL_H > H) @compileError("the scroller runs off the screen");
    if (SCROLL_H != GH) @compileError("the scroller is exactly one IN-font tile tall");
    for (SHADOW_Y) |sy| if (sy + SHADOW_TONE.len > H) @compileError("a shadow strip runs off the screen");
    for (RULE_Y) |ry| if (ry >= H) @compileError("a rule runs off the screen");
    if (LIST_Y + (LIST_INK.len - 1) * LIST_STEP + PH > H) @compileError("the list runs off the screen");
    if (LIST_X + LIST_COLS * PW > W) @compileError("the list runs off the right edge");

    if (cycle.len != CYCLE_TILES * CYCLE_W * CYCLE_H) @compileError("cycle.raw is not 8 tiles of 32x5");
    if (main_img.len != @as(usize, W) * H) @compileError("main.raw is not 320x270");
    if (wait_img.len != @as(usize, W) * H) @compileError("wait.raw is not 320x270");
    if (fontin.len != GLYPHS * GW * GH) @compileError("fontin.raw is not 70 tiles of 32x16");
    if (fontout.len != GLYPHS * GW * GH) @compileError("fontout.raw is not 70 tiles of 32x16");
    if (fontp.len != P_GLYPHS * PW * PH) @compileError("fontp.raw is not 64 tiles of 8x8");
    if (shadow_lut.len != 2 * 256) @compileError("shadow.dat is not two 256-entry LUTs");
    if (scrolltext.len == 0) @compileError("the scrolltext is empty");
}
