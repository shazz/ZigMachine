// --------------------------------------------------------------------------
// The other three renderers. All four take the SAME intensity grid from
// shade.zig and draw it with a different blitter capability, so the screen is a
// bench: only the technique changes.
//
//   1 DOT SIZE   BLIT, one per lit cell, ten dots in a sheet (dots.zig)
//   2 HALFTONE   FILL + the HALFTONE register, one per RUN of equal cells
//   3 SOLID      FILL, one per run, the palette ramp — the baseline
//   4 FILL DOTS  FILL, one per lit cell, a square whose side is the intensity
//
// The teaching contrast is 1 against 2. A sheet can change the DOT, so every
// cell needs its own blit. The halftone register cannot: it is one fixed 16x16
// 1-bit mask for the whole op, so cells that share an intensity can be covered
// by ONE fill — far fewer operations, and a picture made of density instead of
// dot size. That is the trade the ST's blitter actually offered.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const shade = @import("shade.zig");
const dots = @import("dots.zig");

const CELL = dots.CELL;
const X_OFF = dots.X_OFF;
const Y_OFF = dots.Y_OFF;
const LEVELS = 10;

pub const Mode = enum(u8) { dot_size, halftone, solid, fill_dots };
pub const NAMES = [_][]const u8{ "DOT SIZE", "HALFTONE", "SOLID", "FILL DOTS" };

pub const Cost = dots.Cost;

// Ink pixels in each of pat.png's ten dots, measured off the asset: the
// original's own intensity ramp. Every mode below derives its shading from it,
// so all four show the SAME ramp expressed differently.
const INK = [LEVELS]u8{ 0, 1, 5, 9, 13, 17, 25, 37, 45, 49 };

// Density, in bits of a 64-pixel Bayer tile: INK scaled from /49 to /64.
const DENSITY = [LEVELS]u8{ 0, 1, 7, 12, 17, 22, 33, 48, 59, 64 };

// Side of the square dot: round(sqrt(INK)), so the square covers the same area
// the sheet's round dot does.
const SIDE = [LEVELS]u8{ 0, 1, 2, 3, 4, 4, 5, 6, 7, 7 };

const BAYER = [8][8]u8{
    .{ 0, 32, 8, 40, 2, 34, 10, 42 },
    .{ 48, 16, 56, 24, 50, 18, 58, 26 },
    .{ 12, 44, 4, 36, 14, 46, 6, 38 },
    .{ 60, 28, 52, 20, 62, 30, 54, 22 },
    .{ 3, 35, 11, 43, 1, 33, 9, 41 },
    .{ 51, 19, 59, 27, 49, 17, 57, 25 },
    .{ 15, 47, 7, 39, 13, 45, 5, 37 },
    .{ 63, 31, 55, 23, 61, 29, 53, 21 },
};

/// One 16x16 halftone pattern per intensity, ordered-dithered: bit set where
/// the Bayer threshold falls under that level's density, so level L lights
/// exactly DENSITY[L] of every 64 pixels. The register is 16 rows of 16 bits
/// and the tile is 8x8, so each row is its byte repeated.
const PATTERNS = blk: {
    @setEvalBranchQuota(LEVELS * 16 * 16 * 4);
    var out: [LEVELS][16]u16 = undefined;
    for (0..LEVELS) |lvl| for (0..16) |y| {
        var row: u16 = 0;
        for (0..16) |x| {
            if (BAYER[y % 8][x % 8] < DENSITY[lvl]) row |= @as(u16, 1) << @intCast(x);
        }
        out[lvl][y] = row;
    };
    break :blk out;
};

/// End (exclusive) of the run of identical cells starting at `start` in `row`.
fn runEnd(grid: *const shade.Grid, row: usize, start: usize) usize {
    const v = grid[row * shade.CELLS_X + start];
    var cx = start + 1;
    while (cx < shade.CELLS_X and grid[row * shade.CELLS_X + cx] == v) : (cx += 1) {}
    return cx;
}

fn rect(bl: *zg.Blitter, fb: *zg.LogicalFB, cx: usize, cy: usize, cells: usize, color: u8, cost: *Cost) void {
    const x: i16 = X_OFF + @as(i16, @intCast(cx * CELL));
    const y: i16 = Y_OFF + @as(i16, @intCast(cy * CELL));
    bl.fill(fb, x, y, @intCast(cells * CELL), CELL, color);
    cost.ops += 1;
    cost.px += bl.cycles();
}

/// MODE 3. One FILL per run of equal cells, straight out of the palette ramp.
/// The cheapest renderer and the one that needs a colour per intensity — which
/// is exactly what an ST screen in four colours did not have.
pub fn solid(fb: *zg.LogicalFB, bl: *zg.Blitter, grid: *const shade.Grid) Cost {
    var cost = Cost{};
    for (0..shade.CELLS_Y) |cy| {
        var cx: usize = 0;
        while (cx < shade.CELLS_X) {
            const end = runEnd(grid, cy, cx);
            const v = grid[cy * shade.CELLS_X + cx];
            if (v != 0) rect(bl, fb, cx, cy, end - cx, dots.INK_BASE + (v - 1), &cost);
            cx = end;
        }
    }
    return cost;
}

/// Which intensities appear in this frame's grid, as a bitmask over 1..10, so
/// the halftone pass only loads the patterns it will actually use.
fn levelsPresent(grid: *const shade.Grid) u16 {
    var mask: u16 = 0;
    for (grid) |v| mask |= @as(u16, 1) << @intCast(v);
    return mask;
}

/// MODE 2. ONE ink and the HALFTONE register: intensity is the DENSITY of a
/// fixed 16x16 pattern, and the pattern is anchored to screen coordinates, so
/// neighbouring cells of the same intensity join into one continuous dither —
/// which is why a whole run can be covered by a single FILL. `loads` counts the
/// pattern changes, the only per-intensity cost.
pub fn halftone(fb: *zg.LogicalFB, bl: *zg.Blitter, grid: *const shade.Grid, loads: *u32) Cost {
    var cost = Cost{};
    const present = levelsPresent(grid);
    loads.* = 0;
    // Level 0 has no ink at all (INK[0] = 0) and an all-zero pattern would turn
    // the halftone OFF, so it is skipped: the field is already black.
    for (1..LEVELS) |lvl| {
        if (present & (@as(u16, 1) << @intCast(lvl + 1)) == 0) continue;
        bl.setHalftone(PATTERNS[lvl]);
        loads.* += 1;
        fillLevel(fb, bl, grid, @intCast(lvl + 1), &cost);
    }
    return cost;
}

/// Every run of cells holding `value`, filled with the pattern already loaded.
fn fillLevel(fb: *zg.LogicalFB, bl: *zg.Blitter, grid: *const shade.Grid, value: u8, cost: *Cost) void {
    for (0..shade.CELLS_Y) |cy| {
        var cx: usize = 0;
        while (cx < shade.CELLS_X) {
            const end = runEnd(grid, cy, cx);
            // COLOR is the brightest ink, BG_COLOR stays 0 (nothing in this
            // scene writes it), so a clear bit leaves the black field.
            if (grid[cy * shade.CELLS_X + cx] == value) rect(bl, fb, cx, cy, end - cx, dots.INK_TOP, cost);
            cx = end;
        }
    }
}

/// MODE 4. No source art at all: a centred square whose SIDE is the intensity,
/// one constant FILL per lit cell. Same op count as mode 1, same ramp, but the
/// blitter never fetches a source pixel — the difference between the two is the
/// cost of the source channel.
pub fn fillDots(fb: *zg.LogicalFB, bl: *zg.Blitter, grid: *const shade.Grid) Cost {
    var cost = Cost{};
    for (0..shade.CELLS_Y) |cy| for (0..shade.CELLS_X) |cx| {
        const v = grid[cy * shade.CELLS_X + cx];
        if (v == 0) continue;
        const side = SIDE[v - 1];
        if (side == 0) continue; // the darkest level draws nothing
        const pad: i16 = @intCast((CELL - side) / 2);
        const x: i16 = X_OFF + @as(i16, @intCast(cx * CELL)) + pad;
        const y: i16 = Y_OFF + @as(i16, @intCast(cy * CELL)) + pad;
        bl.fill(fb, x, y, side, side, dots.INK_BASE + (v - 1));
        cost.ops += 1;
        cost.px += bl.cycles();
    };
    return cost;
}
