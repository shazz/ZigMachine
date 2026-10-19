// --------------------------------------------------------------------------
// Union main -- the tile world as pre-composited 16x16 cells.
//
// The three tile layers (clouds, animated rows, world) all sit on the same
// 16 px grid (rows 35 + 16r), and were drawn clouds -> anim -> world with
// colour 0 transparent. A map cell is therefore the same 16x16 picture however
// often it comes round, so it is composited ONCE, here, at compile time: the
// frame draws one keyed CHISEL blit per non-empty cell (about 64 a frame)
// instead of up to 390 tiles through the CPU's keyed row copies.
//
// The generator is this comptime block: it paints the cell of every distinct
// (clouds, anim, world) id triple with the very same layer order and keys as
// tilemap.Layer.draw, so a cell's pixels are what the three tile blits left.
// --------------------------------------------------------------------------
const maps = @import("../../assets/screens/union_main/union_maps.zig");

const tileset_raw = @embedFile("../../assets/screens/union_main/tileset.raw");
const gradtiles_raw = @embedFile("../../assets/screens/union_main/gradtiles.raw");
const world_dat = @embedFile("../../assets/screens/union_main/world.dat");
const anim_dat = @embedFile("../../assets/screens/union_main/anim.dat");
const clouds_dat = @embedFile("../../assets/screens/union_main/clouds.dat");

pub const W = maps.WORLD_W; // 802 columns (incl. the wrap tail)
pub const ROWS = maps.WORLD_ROWS; // 9 rows of 16 px from y = TOP
pub const TOP: i16 = 35;
pub const CELL: usize = 16;
pub const NONE: u8 = 0xFF; // an empty cell: nothing to draw

const CLOUD_ROW = 6; // clouds_layer.dst_y 131 = 35 + 6 * 16
const ANIM_ROW0 = 3; // anim_layer.dst_y 83 = 35 + 3 * 16
const ANIM_ROWS = maps.ANIM_ROWS;

const Key = struct { c: u8, a: u8, w: u8 };

fn keyAt(r: usize, x: usize) Key {
    var k = Key{ .c = 0, .a = 0, .w = world_dat[r * W + x] };
    if (r == CLOUD_ROW and clouds_dat[x] >= 1) k.c = clouds_dat[x];
    if (r >= ANIM_ROW0 and r < ANIM_ROW0 + ANIM_ROWS and anim_dat[(r - ANIM_ROW0) * W + x] >= 120) k.a = anim_dat[(r - ANIM_ROW0) * W + x];
    return k;
}

/// Paint tile `t` of `sheet` over `cell`, colour 0 transparent.
fn paint(cell: *[CELL * CELL]u8, src: []const u8, sheet_w: usize, cols: usize, t: usize) void {
    const sx = (t % cols) * CELL;
    const sy = (t / cols) * CELL;
    for (0..CELL) |y| for (0..CELL) |x| {
        const p = src[(sy + y) * sheet_w + sx + x];
        if (p != 0) cell[y * CELL + x] = p;
    };
}

const Built = struct {
    ids: [ROWS * W]u8, // row-major cell id per map cell, NONE when empty
    n: usize, // distinct non-empty cells
};

const built: Built = blk: {
    @setEvalBranchQuota(20_000_000);
    var ids: [ROWS * W]u8 = undefined;
    var keys: [256]Key = undefined;
    var n: usize = 0;
    for (0..ROWS) |r| for (0..W) |x| {
        const k = keyAt(r, x);
        if (k.c == 0 and k.a == 0 and k.w == 0) {
            ids[r * W + x] = NONE;
            continue;
        }
        var found: ?usize = null;
        for (keys[0..n], 0..) |o, i| {
            if (o.c == k.c and o.a == k.a and o.w == k.w) found = i;
        }
        if (found == null) {
            keys[n] = k;
            found = n;
            n += 1;
        }
        ids[r * W + x] = @intCast(found.?);
    };
    break :blk .{ .ids = ids, .n = n };
};

/// The cells as one picture, 16 px wide, cell i at rows 16i..16i+15.
pub const sheet: [built.n * CELL * CELL]u8 = blk: {
    @setEvalBranchQuota(20_000_000);
    var keys: [256]Key = undefined;
    var seen: [256]bool = [_]bool{false} ** 256;
    var out = [_]u8{0} ** (built.n * CELL * CELL);
    for (0..ROWS) |r| for (0..W) |x| {
        const id = built.ids[r * W + x];
        if (id == NONE or seen[id]) continue;
        seen[id] = true;
        keys[id] = keyAt(r, x);
        var cell = [_]u8{0} ** (CELL * CELL);
        const k = keys[id];
        if (k.c != 0) paint(&cell, tileset_raw, 272, 17, k.c - 1); // clouds: tileset, id_base 1
        if (k.a != 0) paint(&cell, gradtiles_raw, 128, 8, k.a - 120); // anim: gradTiles, id_base 120
        if (k.w != 0) paint(&cell, tileset_raw, 272, 17, k.w - 1); // world: tileset, id_base 1
        @memcpy(out[id * CELL * CELL ..][0 .. CELL * CELL], &cell);
    };
    break :blk out;
};

/// Cell id (or NONE) of map row `r`, column `x`.
pub fn idAt(r: usize, x: usize) u8 {
    return built.ids[r * W + x];
}

test "the cell sheet holds every distinct cell" {
    const std = @import("std");
    try std.testing.expect(built.n > 100 and built.n < 256);
    try std.testing.expectEqual(NONE, idAt(0, 0));
}
