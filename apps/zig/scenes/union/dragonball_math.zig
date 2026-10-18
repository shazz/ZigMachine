// --------------------------------------------------------------------------
// Dragonball geometry — the 11-vertex / 10-triangle 5-point star from
// codef_dragonball.js (this.objvert / this.obj), plus the tiny 3D + raster
// helpers dragonball.zig needs. Pure math, no ZigOS/plane dependency, so it
// stays reusable and keeps dragonball.zig under the 200-line budget.
// --------------------------------------------------------------------------

pub const Vec3 = struct { x: f32, y: f32, z: f32 };
pub const Vec2 = struct { x: f32, y: f32 };

pub const NVERTS: usize = 11;
pub const NTRIS: usize = 10;
pub const NSTARS: usize = 5;

// codef_dragonball.js this.objvert (ff=730, nf=700).
pub const VERTS = [NVERTS]Vec3{
    .{ .x = 212.0, .y = 0.0, .z = 700 },
    .{ .x = 65.45084971003, .y = 47.55282581318, .z = 730 },
    .{ .x = 65.51160277054, .y = 201.6239814479, .z = 700 },
    .{ .x = -25.0, .y = 76.94208843168, .z = 730 },
    .{ .x = -171.5116027705, .y = 124.6104735024, .z = 700 },
    .{ .x = -80.90169942, .y = 0.0, .z = 730 },
    .{ .x = -171.5116027705, .y = -124.6104735024, .z = 700 },
    .{ .x = -25.0, .y = -76.94208843168, .z = 730 },
    .{ .x = 65.51160277054, .y = -201.6239814479, .z = 700 },
    .{ .x = 65.45084971003, .y = -47.5528258131, .z = 730 },
    .{ .x = 0.0, .y = 0.0, .z = 700 },
};

// codef_dragonball.js this.obj (p1,p2,p3 triples, 1-indexed there -> 0-indexed here).
pub const TRIS = [NTRIS][3]u8{
    .{ 1, 2, 3 },  .{ 3, 4, 5 },  .{ 5, 6, 7 },  .{ 7, 8, 9 },  .{ 9, 0, 1 },
    .{ 1, 3, 10 }, .{ 3, 5, 10 }, .{ 5, 7, 10 }, .{ 7, 9, 10 }, .{ 10, 9, 1 },
};

// Camera: codef3D(dst, camZ=2600, fov=40, ...). Rendered at half-res (64x64
// ball canvas vs the original 128x128), focal kept at the ORIGINAL full-res
// value (64/tan(20deg)) so the star reads at the same relative size inside
// the smaller ball sprite (~10px tip radius) — see Fable's spec.
pub const CAM_Z: f32 = 2600.0;
pub const FOCAL: f32 = 87.9;
pub const BALL_SIZE: usize = 64;
pub const CENTER: f32 = 32.0;

// three.js Euler order 'XYZ' with rotation.z always 0 here reduces to Rx * Ry.
pub fn rotate(v: Vec3, ax: f32, ay: f32) Vec3 {
    const sy = @sin(ay);
    const cy = @cos(ay);
    const x1 = v.x * cy + v.z * sy;
    const z1 = -v.x * sy + v.z * cy;
    const sx = @sin(ax);
    const cx = @cos(ax);
    const y2 = v.y * cx - z1 * sx;
    const z2 = v.y * sx + z1 * cx;
    return .{ .x = x1, .y = y2, .z = z2 };
}

// sx = cx + f*x/(camZ-z), sy = cy - f*y/(camZ-z) (screen Y flips 3D Y-up).
pub fn project(v: Vec3) Vec2 {
    var denom = CAM_Z - v.z;
    if (denom < 1.0) denom = 1.0; // defensive: verts never reach the camera plane
    return .{
        .x = CENTER + FOCAL * v.x / denom,
        .y = CENTER - FOCAL * v.y / denom,
    };
}

// Positive => CCW in screen space (used to split front/back facing triangles).
pub fn signedArea(a: Vec2, b: Vec2, c: Vec2) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

// Flat-fill a triangle into a BALL_SIZE x BALL_SIZE u8 index buffer, clipped
// to its bounds. Odd-even scanline fill, mirrors softTriangle in obj_demo.zig.
pub fn fillTriangle(buf: *[BALL_SIZE * BALL_SIZE]u8, v0: Vec2, v1: Vec2, v2: Vec2, color: u8) void {
    const xs = [3]f32{ v0.x, v1.x, v2.x };
    const ys = [3]f32{ v0.y, v1.y, v2.y };
    var ymin = @min(ys[0], @min(ys[1], ys[2]));
    var ymax = @max(ys[0], @max(ys[1], ys[2]));
    if (ymin < 0) ymin = 0;
    if (ymax > @as(f32, BALL_SIZE - 1)) ymax = @as(f32, BALL_SIZE - 1);
    var y: i32 = @intFromFloat(@ceil(ymin));
    const ylast: i32 = @intFromFloat(@floor(ymax));
    while (y <= ylast) : (y += 1) {
        const fy: f32 = @floatFromInt(y);
        var xl: f32 = 1e9;
        var xr: f32 = -1e9;
        var e: usize = 0;
        while (e < 3) : (e += 1) {
            var ay = ys[e];
            var ax = xs[e];
            var by = ys[(e + 1) % 3];
            var bx = xs[(e + 1) % 3];
            if (ay == by) continue;
            if (ay > by) {
                const ty = ay;
                ay = by;
                by = ty;
                const tx = ax;
                ax = bx;
                bx = tx;
            }
            if (fy < ay or fy >= by) continue;
            const x = ax + (bx - ax) * (fy - ay) / (by - ay);
            xl = @min(xl, x);
            xr = @max(xr, x);
        }
        if (xr < xl) continue;
        var l: i32 = @intFromFloat(@ceil(xl));
        var r: i32 = @intFromFloat(@floor(xr));
        if (l < 0) l = 0;
        if (r > @as(i32, BALL_SIZE - 1)) r = BALL_SIZE - 1;
        if (r < l) continue;
        const row: usize = @as(usize, @intCast(y)) * BALL_SIZE;
        var x: i32 = l;
        while (x <= r) : (x += 1) buf[row + @as(usize, @intCast(x))] = color;
    }
}
