// --------------------------------------------------------------------------
// STCS STARGOOSE — the HBL handlers: the raster (the global border colour and
// plane 0's colour 0, per line) and plane 1's font palette per band.
// Each writes a register only when its value changes (a raster coder never
// rewrites one), and from RGBA word tables: a [256]Color is byte-aligned, and
// its 4-byte loads in the HBLs TRAPPED on the board (~700 cycles each).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const strip = @import("stcs_strip.zig");
const scratch = @import("stcs_scratch.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const SCROLL_CHAR_HEIGHT = scratch.GH;

/// The scroller's shape this frame (stcs.zig's schedule sets it).
pub var period: strip.Period = .threelines;

// palettes (init); the HBLs use their RGBA words (font_words)
pub const font_pal1: [256]Color = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/font40x34_c1_pal.dat"));
const font_pal2: [256]Color = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/font40x34_c2_pal.dat"));
const font_pal3: [256]Color = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/font40x34_c3_pal.dat"));
pub const logo_pal: [256]Color = convertU8ArraytoColors(@embedFile("../assets/screens/stcs/logo_pal.dat"));

// rasters, as the RGBA words the HBLs store: a [256]Color is byte-aligned
// whatever it is declared with, and its 4-byte loads trapped on the board.
const rasters_b: [256]u32 = words(convertU8ArraytoColors(@embedFile("../assets/screens/stcs/rasters.dat")));

const BLACK: u32 = 0; // Color{ 0, 0, 0, 0 }

// What the global HBL and plane 0's HBL last wrote (RGBA; null after init): a
// raster coder never rewrites a register that already holds the right colour,
// and below line 239 both hold the last raster colour for 40-odd lines.
var last_bg: ?u32 = null;
var last_pal0: ?u32 = null;

/// At scene init: nothing is known to be in the registers yet.
pub fn reset() void {
    last_bg = null;
    last_pal0 = null;
    scroller_pal = null; // plane 1's entry 0 is not font_pal1's: the first line installs it
}

pub fn global(zigos: *ZigOS, line: u16) void {
    // GLOBAL HBL — fires on PHYSICAL lines 0..279 (borders included). The raster
    // gradient runs 107..239, then HOLDS its last colour on into the low border
    // (240..279) instead of going black. Above the raster stays black.
    const c: u32 = if (line > 40 + 66) rasters_b[@min(line - 40 - 66, 133)] else BLACK;
    if (last_bg != c) {
        zigos.setBackgroundColor(Color.fromRGBA(c));
        last_bg = c;
    }
}

/// ZIG MODE's open side borders (stcs_zig.zig key 1): flicker every visible line.
pub var open_sides = false;

/// Plane 1's HBL: the scroller's band palettes (entries 1..15), and in entry 0
/// the raster the logo's plane 0 held before the logo moved into plane 1
/// (stcs_logo.zig): plane 1's entry 0 was transparent and showed it.
/// Plane 1 is an OVERSCAN plane (for ZIG MODE), so this fires at
/// OVERSCAN_MAGIC_X on PHYSICAL lines 0..279; the window's lines 40..239 are
/// the logical 0..199 it used to get, and the border bands are left alone
/// (closed, they show none of the plane), so ORIGINAL is unchanged.
pub fn plane(fb: *LogicalFB, zigos: *ZigOS, phys: u16, col: u16) void {
    _ = zigos;
    _ = col;
    if (phys < zg.VERTICAL_BORDERS_HEIGHT or phys >= zg.VERTICAL_BORDERS_HEIGHT + zg.HEIGHT) return;
    const line = phys - zg.VERTICAL_BORDERS_HEIGHT;
    scroller(fb, line);
    logoRaster(fb, line);
    // the open sides show this line's entry 0 where nothing is drawn: the
    // raster's colour, which is the closed border's (global), so it runs on
    if (open_sides) fb.flickerBorder();
}

fn logoRaster(fb: *LogicalFB, line: u16) void {
    // `line` is the window's (0..199; plane() dropped the border's 40).
    // Rasters cover visible rows 66..199.
    const c: u32 = if (line > 66 and line < 200) rasters_b[line - 66] else BLACK;
    if (last_pal0 != c) {
        fb.palette[0] = c;
        last_pal0 = c;
    }
}

// The palette a line of the scroller plane wants. The HBL used to copy all 256
// entries on EVERY line (51,200 stores a frame, each a bus write on the board);
// the bands change it at most 3 times a frame, so it is installed only on a change.
fn scrollerPalette(line: u16) u2 {
    return switch (period) {
        .threelines => switch (line) {
            84...84 + SCROLL_CHAR_HEIGHT + 5 => 0,
            84 + SCROLL_CHAR_HEIGHT + 5 + 1...84 + 2 * (SCROLL_CHAR_HEIGHT + 5) => 1,
            84 + 2 * (SCROLL_CHAR_HEIGHT + 5) + 1...200 => 2,
            else => 0,
        },
        .inverted_mirror => switch (line) {
            84...117 => 0,
            118...150 => 1,
            151...200 => 2,
            else => 0,
        },
        .inverted => switch (line) {
            84...140 => 0,
            141...200 => 1,
            else => 0,
        },
        else => 0,
    };
}

// font_pal1..3 as the RGBA words the palette holds. A [256]Color is byte-aligned
// and its 4-byte loads in the HBLs TRAPPED on the board (~700 cycles each).
const font_words: [3][256]u32 = .{ words(font_pal1), words(font_pal2), words(font_pal3) };
fn words(comptime pal: [256]Color) [256]u32 {
    @setEvalBranchQuota(10_000);
    var out: [256]u32 = undefined;
    for (pal, 0..) |c, i| out[i] = c.toRGBA();
    return out;
}

// The font palette plane 1 holds now (null: none of the three, as after init).
var scroller_pal: ?u2 = null;

fn scroller(fb: *LogicalFB, line: u16) void {
    const want = scrollerPalette(line);
    if (scroller_pal != want) {
        // Store only the entries that change, and only the 16 the plane's pixels
        // can hold (scratch.COLORS: the font's; the three palettes differ in 246
        // entries, all above 15, that no pixel of plane 1 ever shows). Once a
        // font palette is in, the plane holds its words, so compare those (cart
        // RAM) instead of reading the palette back; after init, the palette itself.
        // Entry 0 is the raster's (logoRaster); every font palette has it
        // transparent, which is what let the logo's plane show through it.
        const to = font_words[want][1..scratch.COLORS];
        if (scroller_pal) |held| {
            for (to, font_words[held][1..scratch.COLORS], 1..) |v, was, i| if (v != was) { fb.palette[i] = v; };
        } else {
            for (to, 1..) |v, i| if (fb.palette[i] != v) { fb.palette[i] = v; };
        }
        scroller_pal = want;
    }
}

comptime {
    for (font_words) |pal| if (pal[0] != 0) @compileError("a font palette's entry 0 is not transparent");
}
