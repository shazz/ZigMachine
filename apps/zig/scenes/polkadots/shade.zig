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
// --------------------------------------------------------------------------
const c3 = @import("zigos").zig3d;

pub const CELLS_X = 45; // 45 x 7 = 315 of the 320 columns
pub const CELLS_Y = 28; // 28 x 7 = 196 of the 200 rows
pub const SS = 4; // supersamples per cell axis
const SW = CELLS_X * SS;
const SH = CELLS_Y * SS;
const SSF: f64 = @floatFromInt(SS);
const SWF: f64 = @floatFromInt(SW);
const SHF: f64 = @floatFromInt(SH);

// new codef3D(mycanvaspetit, 400, 40, 1, 21600) — screen.js:78.
pub const CAM_Z: f64 = 400.0;
pub const FOV: f64 = 40.0;
pub const NEAR: f64 = 1.0;
pub const FAR: f64 = 21600.0;

const AMBIENT: f64 = 17.0 / 255.0; // 0x111111
const DIRECT: f64 = 238.0 / 255.0; // 0xeeeeee
// (0, 1, 0.5).normalize(), done once by addDirLight.
const LX: f64 = 0.0;
const LY: f64 = 0.8944271909999159;
const LZ: f64 = 0.4472135954999579;

// `shit = Math.floor(imgPixels.data[i] * 0.0392156862745)` — screen.js:129.
// The literal is a hair under 1/25.5, so red 255 floors to 9, not to the
// eleventh tile that does not exist. Kept verbatim for that reason.
const TILE_SCALE: f64 = 0.0392156862745;

var samples: [SW * SH]u8 = undefined;

pub const Grid = [CELLS_X * CELLS_Y]u8;

/// Render `mesh` turned by `rotation` and reduce it to one intensity byte per
/// cell: 0 where the canvas stayed black (the original draws no tile there),
/// else 1 + the tile number, so a caller can test the byte and index in one go.
pub fn render(
    lens: *const c3.Lens,
    mesh: *const c3.Mesh,
    rotation: c3.Vec3,
    screen: []c3.Screen,
    polys: []c3.Poly,
    out: *Grid,
) void {
    const origin = c3.Vec3{ .x = 0, .y = 0, .z = 0 };
    const model = c3.Mat4.compose(origin, rotation);
    @memset(&samples, 0);
    const drawn = c3.project(lens, .{ .x = 0, .y = 0, .z = CAM_Z }, origin, rotation, mesh, screen, polys);
    for (drawn) |p| fillQuad(p, redOf(&model, p.ink));
    reduce(out);
}

/// The face colour's red byte. `ink` is the face's index in the mesh, which
/// torus.zig stores there so the normal survives zig3d's depth sort.
fn redOf(model: *const c3.Mat4, ink: u8) u8 {
    const n = normals[ink];
    const e = model.e;
    const wx = @as(f64, e[0]) * n.x + @as(f64, e[4]) * n.y + @as(f64, e[8]) * n.z;
    const wy = @as(f64, e[1]) * n.x + @as(f64, e[5]) * n.y + @as(f64, e[9]) * n.z;
    const wz = @as(f64, e[2]) * n.x + @as(f64, e[6]) * n.y + @as(f64, e[10]) * n.z;
    const dot = wx * LX + wy * LY + wz * LZ;
    var v = AMBIENT;
    if (dot > 0) v += DIRECT * dot;
    if (v > 1.0) v = 1.0;
    return @intFromFloat(@floor(255.0 * v));
}

/// The scene hands its geometry's face normals over once, at init.
var normals: []const c3.Vec3 = &.{};

pub fn setNormals(n: []const c3.Vec3) void {
    normals = n;
}

/// zig3d gives canvas pixels for a CELLS_X x CELLS_Y canvas (so its 1 px
/// overdraw is the original's 1 px); the supersample grid is SS times that.
fn fillQuad(p: c3.Poly, red: u8) void {
    var pts: [4][2]f64 = undefined;
    var top: f64 = 1e9;
    var bot: f64 = -1e9;
    for (0..p.n) |i| {
        pts[i] = .{ p.pts[i][0] * SSF, p.pts[i][1] * SSF };
        top = @min(top, pts[i][1]);
        bot = @max(bot, pts[i][1]);
    }
    const y0: usize = @intFromFloat(@max(0.0, @floor(top)));
    const y1: usize = @intFromFloat(@min(SHF - 1.0, @ceil(bot)));
    var y = y0;
    while (y <= y1) : (y += 1) span(&pts, p.n, y, red);
}

/// One scanline of the polygon, even-odd: the 1 px overdraw can make a quad
/// very slightly non-convex, so min/max of the crossings is not enough.
fn span(pts: *const [4][2]f64, n: u8, y: usize, red: u8) void {
    const py = @as(f64, @floatFromInt(y)) + 0.5;
    var xs: [4]f64 = undefined;
    var m: usize = 0;
    for (0..n) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % n];
        if ((a[1] <= py and py < b[1]) or (b[1] <= py and py < a[1])) {
            xs[m] = a[0] + (py - a[1]) * (b[0] - a[0]) / (b[1] - a[1]);
            m += 1;
        }
    }
    if (m < 2) return;
    var lo = xs[0];
    var hi = xs[0];
    for (xs[1..m]) |x| {
        lo = @min(lo, x);
        hi = @max(hi, x);
    }
    paint(lo, hi, y, red);
}

fn paint(lo: f64, hi: f64, y: usize, red: u8) void {
    if (hi < 0.5 or lo > SWF - 0.5) return;
    const xa: usize = @intFromFloat(@max(0.0, @ceil(lo - 0.5)));
    const xb_f = @min(SWF - 1.0, @floor(hi - 0.5));
    if (xb_f < @as(f64, @floatFromInt(xa))) return;
    const xb: usize = @intFromFloat(xb_f);
    @memset(samples[y * SW + xa .. y * SW + xb + 1], red);
}

/// Average each cell's SS x SS samples (the browser's antialiased pixel), then
/// quantise to a tile. 0 means "canvas still black": no tile is stamped.
fn reduce(out: *Grid) void {
    for (0..CELLS_Y) |cy| for (0..CELLS_X) |cx| {
        var sum: u32 = 0;
        for (0..SS) |j| {
            const row = (cy * SS + j) * SW + cx * SS;
            for (samples[row .. row + SS]) |s| sum += s;
        }
        const red = sum / (SS * SS);
        out[cy * CELLS_X + cx] = if (red == 0) 0 else 1 + tileOf(@intCast(red));
    };
}

fn tileOf(red: u8) u8 {
    return @intFromFloat(@floor(@as(f64, @floatFromInt(red)) * TILE_SCALE));
}
