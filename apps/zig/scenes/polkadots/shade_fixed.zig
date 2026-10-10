// --------------------------------------------------------------------------
// The default cart's renderer: the small canvas of shade.zig drawn in
// INTEGERS, the way an ST coder would draw a flat-shaded torus.
//
//   light    N_world . L = N . (R^T L): the light is turned back into the
//            model once a frame, so each face costs three multiplies (the
//            float port rotated every face normal)
//   fill     each edge walks its scanlines with a Q16 x and a constant step
//            (one 32-bit divide per edge), writing the row's leftmost and rightmost
//            crossing; then one memset per row. The float port solved every
//            edge on every row with a divide.
//
// Same canvas, same rule for what a row covers (pixel centres, the outermost
// crossings), so the dots differ from polkadots_f32's only where a rounding
// lands a crossing on the other side of a sample centre.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const c3 = zg.zig3d;
const trig = zg.fixtrig;
const shade = @import("shade.zig");
const torus = @import("torus.zig");
const P = @import("project_fixed.zig");

const ONE: i32 = 1 << 16;
const HALF: i32 = 1 << 15;
const L = P.V3{ .x = 0, .y = @round(shade.LY * 65536.0), .z = @round(shade.LZ * 65536.0) };

/// The turn: two integer angles, so they wrap exactly instead of growing.
pub const Rotation = struct {
    x: trig.Angle,
    y: trig.Angle,

    pub fn init(self: *Rotation) void {
        self.* = .{ .x = 0, .y = 0 };
    }

    pub fn step(self: *Rotation, comptime dx: comptime_float, comptime dy: comptime_float) void {
        self.x +%= trig.angle(dx);
        self.y +%= trig.angle(dy);
    }
};

const Tables = struct {
    verts: [torus.VERTS]P.V3,
    centroids: [torus.FACES]P.V3,
    normals: [torus.FACES]P.V3,
    quads: [torus.FACES]P.Quad,
};

var t: *Tables = undefined;
var faces: []const c3.Face = &.{};
var lens: P.Lens = undefined;

/// The torus, once per cart load, in Q16 (built in f64 by torus.zig).
pub fn init(geometry: *const torus.Geometry, mesh: *const c3.Mesh) void {
    t = &zg.mem.mustAlloc(Tables, 1)[0];
    for (&t.verts, geometry.verts) |*d, s| d.* = P.q16(s);
    for (&t.centroids, mesh.centroids) |*d, s| d.* = P.q16(s);
    for (&t.normals, geometry.normals) |*d, s| d.* = P.q16(s);
    faces = mesh.faces;
    lens = P.Lens.init();
}

/// Render the torus turned by `rot` and reduce it to one intensity byte a cell.
pub fn render(rot: *const Rotation, out: *shade.Grid) void {
    const m = P.rotation(rot.x, rot.y);
    // R^T L: the light in model space
    const lm = P.V3{
        .x = P.dot(.{ .x = m[0].x, .y = m[1].x, .z = m[2].x }, L),
        .y = P.dot(.{ .x = m[0].y, .y = m[1].y, .z = m[2].y }, L),
        .z = P.dot(.{ .x = m[0].z, .y = m[1].z, .z = m[2].z }, L),
    };
    @memset(shade.samples, 0);
    for (P.project(&lens, &m, &t.verts, &t.centroids, faces, &t.quads)) |i| fillQuad(&t.quads[i], redOf(t.normals[i], lm));
    shade.reduce(out);
}

/// floor(255 * min(1, ambient + direct * max(0, N . L))), with the 255s
/// cancelled: 17 + 238 * dot, floored.
fn redOf(n: P.V3, lm: P.V3) u8 {
    const d = P.dot(n, lm);
    const v: i32 = shade.AMBIENT * ONE + (if (d > 0) shade.DIRECT * d else 0);
    return @intCast(@min(255, v >> 16));
}

var lo: [shade.SH]i32 = undefined;
var hi: [shade.SH]i32 = undefined;
var hits: [shade.SH]u8 = undefined;

/// One face into the supersampled canvas (SS times the projection's pixels).
fn fillQuad(q: *const P.Quad, red: u8) void {
    var pts: P.Quad = undefined;
    var top: i32 = shade.SH * ONE;
    var bot: i32 = -ONE;
    for (q, &pts) |p, *d| {
        d.* = .{ p[0] * shade.SS, p[1] * shade.SS };
        top = @min(top, d[1]);
        bot = @max(bot, d[1]);
    }
    const top_row = @max(0, top >> 16); // floor(top)
    const bot_row = @min(shade.SH - 1, (bot + ONE - 1) >> 16); // ceil(bot)
    if (top_row > bot_row) return;
    const y0: usize = @intCast(top_row);
    const y1: usize = @intCast(bot_row);
    for (y0..y1 + 1) |y| {
        lo[y] = shade.SW * ONE;
        hi[y] = -ONE;
        hits[y] = 0;
    }
    for (0..4) |i| edge(pts[i], pts[(i + 1) % 4], y0, y1);
    for (y0..y1 + 1) |y| {
        if (hits[y] < 2) continue;
        if (hi[y] < HALF or lo[y] > shade.SW * ONE - HALF) continue;
        const xa: i32 = @max(0, (lo[y] + HALF - 1) >> 16); // ceil(lo - 0.5)
        const xb: i32 = @min(shade.SW - 1, (hi[y] - HALF) >> 16); // floor(hi - 0.5)
        if (xb < xa) continue;
        shade.fillRow(y, @intCast(xa), @intCast(xb), red);
    }
}

/// Every row whose pixel centre y + 0.5 lies in [top, bottom) of the edge
/// gets the edge's x there: the float port's crossing rule, stepped.
fn edge(a: [2]i32, b: [2]i32, y0: usize, y1: usize) void {
    if (a[1] == b[1]) return;
    const p = if (a[1] < b[1]) a else b;
    const r = if (a[1] < b[1]) b else a;
    const first: i32 = @max(@as(i32, @intCast(y0)), (p[1] + HALF - 1) >> 16);
    const last: i32 = @min(@as(i32, @intCast(y1)), ((r[1] + HALF - 1) >> 16) - 1);
    if (first > last) return;
    const slope = slopeOf(r[0] - p[0], r[1] - p[1]);
    var x: i32 = p[0] + @as(i32, @intCast((@as(i64, first) * ONE + HALF - p[1]) * slope >> 16));
    var y: usize = @intCast(first);
    while (y <= last) : (y += 1) {
        lo[y] = @min(lo[y], x);
        hi[y] = @max(hi[y], x);
        hits[y] += 1;
        x += slope;
    }
}

/// dx / dy in Q16, with ONE 32-bit hardware divide: rv32 has no 64-bit
/// divide, and libgcc's cost about a thousand cycles an edge, most of the fill.
/// dx is shifted up as far as 32 bits allow (16 places for an edge under half
/// a sample, 8 for one of 64) and dy down by what is missing, so the quotient
/// keeps the precision the smaller operand has. dy under 1/65536 of what that
/// leaves means the edge crosses one row at most, where its x is anywhere
/// along it: slope 0.
fn slopeOf(dx: i32, dy: i32) i32 {
    const room: u5 = @intCast(@min(16, @clz(@abs(dx)) - 1)); // dx << room fits an i32
    const den = dy >> (16 - room);
    if (den == 0) return 0;
    return @divTrunc(dx << room, den);
}
