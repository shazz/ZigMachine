// --------------------------------------------------------------------------
// The env-mapped "ball-oid" of "Are You Sitting Comfortably?" (EarX/Lineout's engine,
// Delta's BALLOID.SO lineage): 402 vertices (2 poles + 40 rings x 10 longitudes), 410
// faces, env-mapped from the vertex normal. Integer-only per frame (no FPU on ZIGGY).
// The morph is the DSP's own ring-radius formula (ringProfile), read from its program.
// --------------------------------------------------------------------------
const std = @import("std");
const rast = @import("balloid_rast.zig");
const poly = rast.poly;
const gradients = rast.gradients;

pub const Kind = enum { grey, orange };

pub const RINGS = 40;
pub const LONS = 10;
pub const NVERT = 2 + RINGS * LONS; // 402
pub const NFACE = LONS * (RINGS + 1); // 10 top tris + 390 quads + 10 bottom tris = 410
const LAT_STEP = 24; // 2048 = one turn
const NONE: u16 = 0xFFFF; // 4th index of a triangle face

pub var sin_tbl: [2048]i16 = undefined; // amplitude 32767, as the original's table
pub var faces: [NFACE][4]u16 = undefined;
var env_orange: [4096]u16 = undefined;
var env_grey: [4096]u16 = undefined;

pub const SV = struct { x: i32, y: i32, u: i32, v: i32 }; // x,y 28.4 screen; u,v 16.16 texels
var sv: [NVERT]SV = undefined;
var vz: [NVERT]i32 = undefined;
var order: [NFACE]u16 = undefined;
var keys: [NFACE]u8 = undefined;
var vis: [NFACE]u16 = undefined;
var halves: [NFACE]u8 = undefined;

fn sin(a: u32) i32 {
    return sin_tbl[a & 2047];
}
fn cos(a: u32) i32 {
    return sin_tbl[(a +% 512) & 2047];
}
fn rgb(r: u32, g: u32, b: u32) u16 {
    return @intCast((r >> 3) << 11 | (g >> 2) << 5 | b >> 3);
}

pub fn init() void {
    // INIT ONLY: float builds the table once; nothing per frame touches float.
    for (&sin_tbl, 0..) |*s, i| s.* = @intFromFloat(@round(32767.0 * @sin(@as(f64, @floatFromInt(i)) * std.math.pi / 1024.0)));
    var f: usize = 0;
    for (0..LONS) |j| { // top fan, then quads ring by ring, then bottom fan
        faces[f] = .{ 0, @intCast(1 + j), @intCast(1 + (j + 1) % LONS), NONE };
        f += 1;
    }
    for (0..RINGS - 1) |r| for (0..LONS) |j| {
        const a = 1 + r * LONS;
        const j1 = (j + 1) % LONS;
        faces[f] = .{ @intCast(a + j), @intCast(a + LONS + j), @intCast(a + LONS + j1), @intCast(a + j1) };
        f += 1;
    };
    for (0..LONS) |j| {
        const a = 1 + (RINGS - 1) * LONS;
        faces[f] = .{ @intCast(a + j), NVERT - 1, @intCast(a + (j + 1) % LONS), NONE };
        f += 1;
    }
    std.debug.assert(f == NFACE);
    for (0..64) |y| for (0..64) |x| {
        const dx: i32 = @as(i32, @intCast(x)) * 2 - 63; // half-texels from the centre
        const dy: i32 = @as(i32, @intCast(y)) * 2 - 63;
        const d2: u32 = @intCast(dx * dx + dy * dy); // 4096 = the rim
        env_orange[y * 64 + x] = orangeTexel(d2, dx, dy);
        env_grey[y * 64 + x] = greyTexel(std.math.sqrt(d2));
    };
}

// Env maps: texel (u,v) = the normal's screen (x,y), so the map IS the lit sphere.
fn orangeTexel(d2: u32, dx: i32, dy: i32) u16 {
    if (d2 >= 4096) return rgb(24, 6, 0);
    const nz: u32 = std.math.sqrt(4096 - d2); // 0..64: Lambert towards the viewer
    const k = nz * nz / 64; // squared falloff: dark brown rim, bright core
    var r = 40 + 215 * k / 64;
    var g = 10 + 110 * k / 64;
    var b = 30 * k / 64;
    const s2: u32 = @intCast((dx + 22) * (dx + 22) + (dy + 22) * (dy + 22)); // spot up-left
    if (s2 < 144) {
        const w = 144 - s2;
        r += (255 - r) * w / 144;
        g += (255 - g) * w / 144;
        b += (255 - b) * w / 144;
    }
    return rgb(r, g, b);
}

// White core, dark ring, white again, dark grazing rim (the grey object's look).
fn greyTexel(d: u32) u16 {
    const l: u32 = if (d < 20) 255 else if (d < 30) 255 - (d - 20) * 19 else if (d < 40) 65 + (d - 30) * 19 else if (d < 56) 255 else if (d < 64) 255 - (d - 56) * 25 else 40;
    return rgb(l, l, l);
}

pub const Cfg = struct { focal: i32, cx: i32, cy: i32, x0: i32, y0: i32, x1: i32, y1: i32, clear: u16, radius: i32 };
fn cfgOf(k: Kind) Cfg {
    return switch (k) { // radius: object units x64, fitted to the frames (not ripped)
        .orange => .{ .focal = 640, .cx = 160, .cy = 100, .x0 = 90, .y0 = 30, .x1 = 230, .y1 = 170, .clear = 0, .radius = 25 * 64 },
        .grey => .{ .focal = 256, .cx = 273, .cy = 100, .x0 = 160, .y0 = 25, .x1 = 320, .y1 = 175, .clear = 0xFFFF, .radius = 78 * 64 },
    };
}

// Ring r's meridian point (rho, h), the DSP's own formula (read from the running DSP program in
// Hatari, P:$07E8; prototypes/falcon_ays_re/ANALYSIS.md 3.9): the ring's radius factor is
//     f(r) = 0.5 + 0.0625 sin(2 pi (r * morph mod 2048) / 2048)
// (a 2048-entry table the CPU uploads, walked with a stride of `morph`: the bigger the morph,
// the more ridges up the object, +-12.5 % deep), then rho = 400 f sin(lat), h = 400 f cos(lat)
// with lat = (r + 1) x 24/2048 of a turn; the poles stay at +-200. Here f is a Q14 factor on
// `radius` (f = 0.5 -> 1.0), and the height keeps the 5/4 the frames showed (the screen aspect).
fn ringProfile(r: usize, morph: i32, radius: i32) [2]i32 {
    const th: u32 = @intCast((r + 1) * LAT_STEP);
    const idx: u32 = @intCast((@as(u32, @intCast(r)) * @as(u32, @intCast(morph))) & 2047);
    const mult = 16384 + (sin(idx) * 2048 >> 15); // Q14: 1 + 0.125 sin
    const rho = (radius * sin(th) >> 15) * mult >> 14;
    const h = ((radius * cos(th) >> 15) * mult >> 14) * 5 >> 2;
    return .{ rho, h };
}

pub const Balloid = struct {
    kind: Kind,
    env: []const u16,
    t: u32 = 0, // 200 Hz clock since the part started
    z: i32 = 1500, // camera distance, original units

    pub fn start(kind: Kind, env: ?[]const u16) Balloid {
        const e = env orelse if (kind == .orange) env_orange[0..] else env_grey[0..];
        std.debug.assert(e.len >= 4096);
        return .{ .kind = kind, .env = e, .z = if (kind == .orange) 1500 else 300 };
    }

    pub fn advance(self: *Balloid, ticks200: u32) void {
        self.t +%= ticks200;
        if (self.kind == .orange) { // Balloid.zoom: 2 units a tick, stops at 300 in AYS
            self.z = if (self.t >= 600) 300 else 1500 - 2 * @as(i32, @intCast(self.t));
        }
    }

    /// The original's morph: (sin[t & $7FF] + $8000) >> 7, 0..511, 10.24 s period.
    pub fn morph(self: *const Balloid) i32 {
        return (sin(self.t) + 0x8000) >> 7;
    }

    pub fn draw(self: *const Balloid, pixels: [*]align(4) u16, stride: usize) void {
        self.drawMorph(self.morph(), pixels, stride);
    }

    pub fn drawMorph(self: *const Balloid, m: i32, pixels: [*]align(4) u16, stride: usize) void {
        std.debug.assert(stride & 1 == 0); // keeps every row 4-aligned for the u32 stores
        const c = cfgOf(self.kind);
        const env = self.env.ptr;
        clearBox(c, pixels, stride);
        transform(&c, m, self.t, self.z);
        for (order[0..sortFaces()]) |fi| drawFace(&faces[fi], halves[fi], env, pixels, stride, &c);
    }
};

// A convex quad goes out as ONE polygon (one setup, one row walk instead of two) when its
// u,v are nearly affine: the twist uA - uB + uC - uD (how far the quad is from a plane in
// texture space) under TWIST_MAX. The left chain carries the exact u,v, so the rest of the
// row is off by at most about the twist. Twisted quads (the big near-camera faces of the
// grey object) keep two triangles with their own gradients.
const TWIST_MAX = 3 << 16; // 3 texels (16.16), u and v together: merges ~half the quads, no visible change

fn drawFace(f: *const [4]u16, h: u8, env: [*]const u16, pixels: [*]align(4) u16, stride: usize, c: *const Cfg) void {
    const a = &sv[f[0]];
    const b = &sv[f[1]];
    const cc = &sv[f[2]];
    if (h & 1 == 0) { // only the second half faces the camera
        const d = &sv[f[3]];
        return poly(&.{ a, cc, d }, gradients(a, cc, d), env, pixels, stride, c);
    }
    if (h & 2 == 0) return poly(&.{ a, b, cc }, gradients(a, b, cc), env, pixels, stride, c);
    const d = &sv[f[3]];
    if (h == 7) {
        const tw = @abs(a.u - b.u + cc.u - d.u) + @abs(a.v - b.v + cc.v - d.v);
        if (tw < TWIST_MAX) {
            return poly(&.{ a, b, cc, d }, rast.quadGradients(a, b, cc, d), env, pixels, stride, c);
        }
    }
    poly(&.{ a, b, cc }, gradients(a, b, cc), env, pixels, stride, c);
    poly(&.{ a, cc, d }, gradients(a, cc, d), env, pixels, stride, c);
}

// The renderer's own clear: its box only (black / white), u32 stores, x0 and width even.
fn clearBox(c: Cfg, pixels: [*]align(4) u16, stride: usize) void {
    const fill: u32 = @as(u32, c.clear) * 0x10001;
    const w: usize = @intCast(@divExact(c.x1 - c.x0, 2));
    // A plain word loop, not @memset: no byte-granular memset/memory.fill on the cart.
    for (@as(usize, @intCast(c.y0))..@as(usize, @intCast(c.y1))) |y| {
        const row: [*]align(4) u16 = @alignCast(pixels + y * stride + @as(usize, @intCast(c.x0)));
        const row32: [*]u32 = @ptrCast(row);
        for (0..w) |i| row32[i] = fill;
    }
}

// Q14 rotation from the three angles the CPU sends (X, Y, Z axes): M = Rx * Ry * Rz.
fn matrix(t: u32) [3][3]i32 {
    const sx = sin(t * 3 / 4) >> 1;
    const cx = cos(t * 3 / 4) >> 1;
    const sy = sin(t * 7 / 4) >> 1;
    const cy = cos(t * 7 / 4) >> 1;
    const sz = sin(t * 11 / 8) >> 1;
    const cz = cos(t * 11 / 8) >> 1;
    const rx = [3][3]i32{ .{ 16384, 0, 0 }, .{ 0, cx, -sx }, .{ 0, sx, cx } };
    const ry = [3][3]i32{ .{ cy, 0, sy }, .{ 0, 16384, 0 }, .{ -sy, 0, cy } };
    const rz = [3][3]i32{ .{ cz, -sz, 0 }, .{ sz, cz, 0 }, .{ 0, 0, 16384 } };
    return mul3(mul3(rx, ry), rz);
}

fn mul3(a: [3][3]i32, b: [3][3]i32) [3][3]i32 {
    var o: [3][3]i32 = undefined;
    for (0..3) |i| for (0..3) |j| {
        o[i][j] = (a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j]) >> 14;
    };
    return o;
}

// Surface of revolution: vertex = rho * E_j + h * Ey with E_j = M * (cos phi_j, 0, sin phi_j),
// so a vertex costs 6 muls and its normal 4 (only the normal's x,y feed the env map).
fn transform(c: *const Cfg, m: i32, t: u32, zoom: i32) void {
    const mx = matrix(t);
    var e: [LONS + 1][3]i32 = undefined; // e[LONS] = Ey
    for (0..LONS) |j| {
        const phi: u32 = @intCast(j * 2048 / LONS); // the original's 204 step, closed to 2048
        for (0..3) |k| e[j][k] = (mx[k][0] * (cos(phi) >> 1) + mx[k][2] * (sin(phi) >> 1)) >> 14;
    }
    for (0..3) |k| e[LONS][k] = mx[k][1];
    var prof: [RINGS + 2][2]i32 = undefined; // [0] and [RINGS+1] are the poles
    const pole = c.radius * 5 >> 2;
    prof[0] = .{ 0, pole };
    prof[RINGS + 1] = .{ 0, -pole };
    for (0..RINGS) |r| prof[r + 1] = ringProfile(r, m, c.radius);
    const z0 = zoom * 64;
    vertex(c, 0, 0, pole, &.{ 0, 16384 }, &e[0], &e[LONS], z0);
    vertex(c, NVERT - 1, 0, -pole, &.{ 0, -16384 }, &e[0], &e[LONS], z0);
    for (0..RINGS) |r| {
        // Normal from the neighbour rings (central difference, as Balloid.generate).
        const dr = prof[r + 2][0] - prof[r][0];
        const dh = prof[r + 2][1] - prof[r][1];
        const len: i32 = std.math.sqrt(@as(u32, @intCast(dr * dr + dh * dh)));
        const n = [2]i32{ @divTrunc(-dh * 16384, len), @divTrunc(dr * 16384, len) };
        for (0..LONS) |j| vertex(c, 1 + r * LONS + j, prof[r + 1][0], prof[r + 1][1], &n, &e[j], &e[LONS], z0);
    }
}

fn vertex(c: *const Cfg, i: usize, rho: i32, h: i32, n: *const [2]i32, e: *const [3]i32, ey: *const [3]i32, z0: i32) void {
    const x = (rho * e[0] + h * ey[0]) >> 14;
    const y = (rho * e[1] + h * ey[1]) >> 14;
    const z = z0 + ((rho * e[2] + h * ey[2]) >> 14);
    // focal/z in Q18: z >= 64 units keeps k < 2^16 and |x| < 2^14, so x * k fits i32; >> 14 = 28.4.
    const k = @divTrunc(c.focal << 18, @max(z, 64 * 64));
    const nx = (n[0] * e[0] + n[1] * ey[0]) >> 14; // Q14 camera-space normal
    const ny = (n[0] * e[1] + n[1] * ey[1]) >> 14;
    // Clamp to an 800 px window (never reached by this object) so the rasteriser's i32 maths fit.
    sv[i] = .{
        .x = std.math.clamp(c.cx * 16 + ((x * k) >> 14), -240 * 16, 560 * 16),
        .y = std.math.clamp(c.cy * 16 - ((y * k) >> 14), -300 * 16, 500 * 16),
        .u = (32 << 16) + nx * 124, // +-31 texels around the map centre
        .v = (32 << 16) - ny * 124,
    };
    vz[i] = z;
}

/// Screen-space back-face test (y down; the faces wind clockwise seen from outside).
/// i32 is enough: the 800 px clamp bounds each product by 12800^2 < 2^28.
pub fn front(ia: u16, ib: u16, ic: u16) bool {
    const a = &sv[ia];
    const b = &sv[ib];
    const c = &sv[ic];
    return (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y) < 0;
}

// Painter's order: counting sort of the visible faces by mean z into 256 buckets, far first.
fn sortFaces() usize {
    var zmin: i32 = std.math.maxInt(i32);
    var zmax: i32 = std.math.minInt(i32);
    for (vz) |z| {
        zmin = @min(zmin, z);
        zmax = @max(zmax, z);
    }
    const inv: i32 = @divTrunc(255 << 16, zmax - zmin + 1);
    var count = [_]u16{0} ** 257;
    var n: usize = 0;
    for (&faces, 0..) |*f, i| {
        var h: u8 = @as(u8, @intFromBool(front(f[0], f[1], f[2]))) |
            @as(u8, @intFromBool(f[3] != NONE and front(f[0], f[2], f[3]))) << 1;
        // Both halves front: the quad is convex iff the other diagonal's halves are too.
        if (h == 3 and front(f[0], f[1], f[3]) and front(f[1], f[2], f[3])) h = 7;
        halves[i] = h; // bit 0/1: halves facing the camera, 7: draw as one convex polygon
        if (h == 0) continue;
        const d = if (f[3] == NONE) vz[f[0]] else vz[f[3]];
        const zm = @divTrunc(vz[f[0]] + vz[f[1]] + vz[f[2]] + d, 4);
        const key: u8 = @intCast(255 - (((zm - zmin) * inv) >> 16));
        keys[n] = key;
        vis[n] = @intCast(i);
        count[@as(usize, key) + 1] += 1;
        n += 1;
    }
    for (1..257) |b| count[b] += count[b - 1];
    for (0..n) |k| {
        order[count[keys[k]]] = vis[k];
        count[keys[k]] += 1;
    }
    return n;
}
