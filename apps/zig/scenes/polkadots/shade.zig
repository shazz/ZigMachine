// --------------------------------------------------------------------------
// The small canvas: screen.js renders the torus into `mycanvaspetit`, a tiny
// offscreen, and then reads back ONE BYTE per pixel — the red channel — as the
// halftone intensity (screen.js:126-132). So this module never makes a picture,
// it makes an intensity grid.
//
// Flat Lambert, as codef_3d.js's CanvasRenderer computes it for a
// MeshLambertMaterial with the scene's two lights:
//
//   colour = ambient + lightColour * max(0, N_world . L)     clamped to 1
//   red    = floor(255 * colour.r)
//
// ambient 0x111111, directional 0xeeeeee at intensity 1 from (0,1,0.5)
// normalised (screen.js:74-75). The material's own colour is white, so the
// multiply at the end of the renderer's Lambert branch is a no-op.
//
// ANTIALIASING IS PART OF THE LOOK. The browser fills those polygons with
// coverage antialiasing, so an edge pixel's red — and therefore that cell's dot
// size — is a partial value. Nearest-neighbour fills would give the torus a
// hard, blocky rim. SS x SS supersampling per cell reproduces the graded rim;
// it costs ~7000 sample writes a frame because the object is only ~21 cells
// across.
//
// THIS FILE is what both carts share: the canvas, the light, and the
// reduction to cells. Projecting and filling the torus is the cart's number
// back-end: shade_fixed.zig (the default cart, integers) or shade_f32.zig
// (polkadots_f32: the CODEF port's algorithm in f32, for the FPU test).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const CELLS_X = 45; // 45 x 7 = 315 of the 320 columns
pub const CELLS_Y = 28; // 28 x 7 = 196 of the 200 rows
pub const SS = 4; // supersamples per cell axis
pub const SW = CELLS_X * SS;
pub const SH = CELLS_Y * SS;

// new codef3D(mycanvaspetit, 400, 40, 1, 21600) — screen.js:78.
pub const CAM_Z = 400;
pub const FOV = 40.0;
pub const NEAR = 1;
pub const FAR = 21600;

pub const AMBIENT = 17; // 0x111111, out of 255
pub const DIRECT = 238; // 0xeeeeee, out of 255
// (0, 1, 0.5).normalize(), done once by addDirLight.
pub const LX = 0.0;
pub const LY = 0.8944271909999159;
pub const LZ = 0.4472135954999579;

// `shit = Math.floor(imgPixels.data[i] * 0.0392156862745)` — screen.js:129.
// The literal is a hair under 1/25.5, so red 255 floors to 9, not to the
// eleventh tile that does not exist. Kept verbatim for that reason — and
// evaluated once per red value, at compile time, in f64 as the original does.
const TILE_SCALE: f64 = 0.0392156862745;
const TILE: [256]u8 = blk: {
    var t: [256]u8 = undefined;
    for (&t, 0..) |*v, red| v.* = @intFromFloat(@floor(@as(f64, @floatFromInt(red)) * TILE_SCALE));
    break :blk t;
};

/// The small canvas, from the RAM arena (zg.mem) once per cart load: as a
/// module-scope array it was 20 KB of zeros written into the cart binary.
pub var samples: *align(4) [SW * SH]u8 = undefined;
var owned = false;

pub fn alloc() void {
    if (owned) return;
    // word-aligned, so reduce() can read four samples a load
    samples = @ptrCast(zg.mem.mustAlloc(u32, SW * SH / 4)[0 .. SW * SH / 4]);
    owned = true;
}

pub const Grid = [CELLS_X * CELLS_Y]u8;

/// Fill samples xa..xb (inclusive) of supersample row y with `red`.
pub fn fillRow(y: usize, xa: usize, xb: usize, red: u8) void {
    @memset(samples[y * SW + xa .. y * SW + xb + 1], red);
}

/// Average each cell's SS x SS samples (the browser's antialiased pixel), then
/// quantise to a tile. 0 means "canvas still black": no tile is stamped; else
/// 1 + the tile number, so a caller can test the byte and index in one go.
/// A cell's row of four samples is one aligned word, summed two bytes at a
/// time in its two halves (16 samples of 255 still fit 16 bits).
pub fn reduce(out: *Grid) void {
    const words: [*]const u32 = @ptrCast(@alignCast(samples));
    for (0..CELLS_Y) |cy| for (0..CELLS_X) |cx| {
        var acc: u32 = 0;
        for (0..SS) |j| {
            const w = words[((cy * SS + j) * SW + cx * SS) / 4];
            acc += (w & 0x00FF_00FF) + ((w >> 8) & 0x00FF_00FF);
        }
        const red = ((acc & 0xFFFF) + (acc >> 16)) / (SS * SS);
        out[cy * CELLS_X + cx] = if (red == 0) 0 else 1 + TILE[red];
    };
}

comptime {
    if (SS != 4 or SW % 4 != 0) @compileError("reduce() reads a cell's row as one word");
}
