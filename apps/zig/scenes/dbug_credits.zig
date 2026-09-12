// --------------------------------------------------------------------------
// D-BUG credit panel — the data half of the effect (the machine itself lives in
// zigos `effects/charpanel.zig`). Ported from the Codef original vendored next
// to the assets: `screens/dbug/screen.js` (showLetters) + `data.js`.
//
// The original panel is 20x12 cells of 32x28 px on a 768x540 canvas; ours is
// the same grid at 16x14 on a 320x200 plane, i.e. exactly half — which is why
// every measurement below is the original's, halved.
// --------------------------------------------------------------------------
const charpanel = @import("zigos").charpanel;

pub const COLS: u16 = 20;
pub const ROWS: u16 = 12;
pub const CELL_W: u16 = 16;
pub const CELL_H: u16 = 14;

/// Where the panel sits on its plane. 20*16 == 320, so it spans the full width.
pub const X: u16 = 0;
pub const Y: u16 = 32;

/// The seven apparition orders, generated from data.js by tools/dbug_patterns.py.
const patterns = @embedFile("../assets/screens/dbug/patterns.dat");

// letterSizes = [0,8,10,14,18,22,28] and letterSpaces = [0,12,11,9,7,5,2] in the
// original, halved for our 16x14 cells (spaces round up: 11->6, 9->5, 7->4, 5->3).
// The original applies its horizontal inset vertically too, so a settled glyph
// sits one pixel low and its bottom row falls into the cell below — kept, it is
// part of how the panel looks.
const STEPS = [_]charpanel.Step{
    .{ .size = 0, .off = 0 },
    .{ .size = 4, .off = 6 },
    .{ .size = 5, .off = 6 },
    .{ .size = 7, .off = 5 },
    .{ .size = 9, .off = 4 },
    .{ .size = 11, .off = 3 },
    .{ .size = 14, .off = 1 },
};

/// One live cell per zoom step, so the panel never drops a letter.
pub const MAX_LIVE = STEPS.len;

// The four panels, verbatim from data.js. "And" is the original's own lowercase
// slip: neither font sheet carries lowercase, so it renders as a gap here for
// the same reason it does in the original. (data.js also appends a 13th row of
// spaces to each text; nothing ever indexes past cell 239, so it is dropped.)
const PANEL_TEXTS = [_][]const u8{
    // PRESENTS
    "*      *************" ++
        "**  P   ************" ++
        "***  R   ***********" ++
        "****  E   **********" ++
        "*****  S   *********" ++
        "******  E   ********" ++
        "*******  N   *******" ++
        "********  T   ******" ++
        "*********  S   *****" ++
        "**********  .   ****" ++
        "***********  .   ***" ++
        "************  .   **",
    // THE CRACK
    "                    " ++
        "  PRINCE OF PERSIA  " ++
        "  ----------------  " ++
        "                    " ++
        "                    " ++
        "                    " ++
        "    CRACK BY TBE    " ++
        "                    " ++
        "   ALL OTHER FIXES  " ++
        "       BY GGN       " ++
        "                    " ++
        "                    ",
    // THE README
    "********************" ++
        "                    " ++
        " INSIDE THE FOLDER  " ++
        " IMAGES THERE ARE 2 " ++
        "  FOLDERS FOR THE   " ++
        " ENGLISH AND FRENCH " ++
        "TEXTS. JUST COPY THE" ++
        " FILES TO IMAGES TO " ++
        "  SWITCH LANGUAGES  " ++
        "                    " ++
        "                    " ++
        "********************",
    // THE CREDITS
    "********************" ++
        "*                  *" ++
        "*    CODE, FONT    *" ++
        "*   And MUSIC BY   *" ++
        "*   ------------   *" ++
        "* !CUBE/AGGRESSION *" ++
        "*                  *" ++
        "*     LOGO BY      *" ++
        "*     -------      *" ++
        "*   RANDOM/DHFC    *" ++
        "*                  *" ++
        "********************",
};

/// `font` is the 16x14 indexed glyph sheet (ASCII 32 upwards, 0 transparent).
pub fn config(font: []const u8) charpanel.Config {
    return .{
        .cols = COLS,
        .rows = ROWS,
        .cell_w = CELL_W,
        .cell_h = CELL_H,
        .font = font,
        .steps = &STEPS,
        .texts = &PANEL_TEXTS,
        .patterns = patterns,
    };
}

comptime {
    for (PANEL_TEXTS) |t| {
        if (t.len != COLS * ROWS) @compileError("a credit panel text is not 20x12 characters");
    }
    if (patterns.len % (COLS * ROWS) != 0) @compileError("patterns.dat is not a whole number of panels");
}
