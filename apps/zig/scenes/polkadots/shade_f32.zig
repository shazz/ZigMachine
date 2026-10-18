// --------------------------------------------------------------------------
// polkadots_f32's renderer: the CODEF port's algorithm, in f32 (the planned
// FPU is single precision only). project_f32.zig projects and sorts the faces;
// this fills each one into the small canvas as polygon scanlines with float
// edge crossings, and lights it with the float Lambert of shade.zig's header.
// The default cart renders the same canvas in integers (shade_fixed.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const c3 = zg.zig3d;
const shade = @import("shade.zig");
const torus = @import("torus.zig");
const P = @import("project_f32.zig");

const SSF: f32 = shade.SS;
const SWF: f32 = shade.SW;
const SHF: f32 = shade.SH;
const AMBIENT: f32 = @as(f32, shade.AMBIENT) / 255.0;
const DIRECT: f32 = @as(f32, shade.DIRECT) / 255.0;

/// The turn, as the remake accumulates it: two unbounded float angles.
pub const Rotation = struct {
    x: f32,
    y: f32,

    pub fn init(self: *Rotation) void {
        self.* = .{ .x = 0, .y = 0 };
    }

    pub fn step(self: *Rotation, comptime dx: comptime_float, comptime dy: comptime_float) void {
        self.x += dx;
        self.y += dy;
    }
};

const Tables = struct {
    verts: [torus.VERTS]P.V3,
    centroids: [torus.FACES]P.V3,
    normals: [torus.FACES]P.V3,
    screen: P.ScreenBuf,
    polys: [torus.FACES]P.Poly,
    order: [torus.FACES]u16,
};

var t: *Tables = undefined;
var faces: []const c3.Face = &.{};
var lens: P.Lens = undefined;

fn v3(v: c3.Vec3) P.V3 {
    return .{ .x = @floatCast(v.x), .y = @floatCast(v.y), .z = @floatCast(v.z) };
}

/// The torus, once per cart load, in f32 (built in f64 by torus.zig).
pub fn init(geometry: *const torus.Geometry, mesh: *const c3.Mesh) void {
    t = &zg.mem.mustAlloc(Tables, 1)[0];
    for (&t.verts, geometry.verts) |*d, s| d.* = v3(s);
    for (&t.centroids, mesh.centroids) |*d, s| d.* = v3(s);
    for (&t.normals, geometry.normals) |*d, s| d.* = v3(s);
    faces = mesh.faces;
    lens = P.Lens.init();
}

/// Render the torus turned by `rot` and reduce it to one intensity byte a cell.
pub fn render(rot: *const Rotation, out: *shade.Grid) void {
    const m = P.rotation(rot.x, rot.y);
    @memset(shade.samples, 0);
    const drawn = P.project(&lens, &m, &t.verts, &t.centroids, faces, &t.screen, &t.polys, &t.order);
    for (drawn) |i| fillQuad(t.polys[i], redOf(&m, t.polys[i].ink));
    shade.reduce(out);
}

/// The face colour's red byte. `ink` is the face's index in the mesh, which
/// torus.zig stores there so the normal survives the depth sort.
fn redOf(m: *const [3]P.V3, ink: u8) u8 {
    const n = t.normals[ink];
    const wx = m[0].x * n.x + m[0].y * n.y + m[0].z * n.z;
    const wy = m[1].x * n.x + m[1].y * n.y + m[1].z * n.z;
    const wz = m[2].x * n.x + m[2].y * n.y + m[2].z * n.z;
    const dot = wx * shade.LX + wy * shade.LY + wz * shade.LZ;
    var v = AMBIENT;
    if (dot > 0) v += DIRECT * dot;
    if (v > 1.0) v = 1.0;
    return @intFromFloat(@floor(255.0 * v));
}

/// The projection gives small-canvas pixels (so its 1 px overdraw is the
/// original's 1 px); the supersample grid is SS times that.
fn fillQuad(p: P.Poly, red: u8) void {
    var pts: [4][2]f32 = undefined;
    var top: f32 = 1e9;
    var bot: f32 = -1e9;
    for (0..4) |i| {
        pts[i] = .{ p.pts[i][0] * SSF, p.pts[i][1] * SSF };
        top = @min(top, pts[i][1]);
        bot = @max(bot, pts[i][1]);
    }
    const y0: usize = @intFromFloat(@max(0.0, @floor(top)));
    const y1: usize = @intFromFloat(@min(SHF - 1.0, @ceil(bot)));
    var y = y0;
    while (y <= y1) : (y += 1) span(&pts, y, red);
}

/// One scanline of the polygon: the outermost of its edge crossings (the 1 px
/// overdraw can make a quad very slightly non-convex).
fn span(pts: *const [4][2]f32, y: usize, red: u8) void {
    const py = @as(f32, @floatFromInt(y)) + 0.5;
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    var m: usize = 0;
    for (0..4) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % 4];
        if ((a[1] <= py and py < b[1]) or (b[1] <= py and py < a[1])) {
            const x = a[0] + (py - a[1]) * (b[0] - a[0]) / (b[1] - a[1]);
            lo = @min(lo, x);
            hi = @max(hi, x);
            m += 1;
        }
    }
    if (m < 2) return;
    if (hi < 0.5 or lo > SWF - 0.5) return;
    const xa: usize = @intFromFloat(@max(0.0, @ceil(lo - 0.5)));
    const xb_f = @min(SWF - 1.0, @floor(hi - 0.5));
    if (xb_f < @as(f32, @floatFromInt(xa))) return;
    shade.fillRow(y, xa, @intFromFloat(xb_f), red);
}
