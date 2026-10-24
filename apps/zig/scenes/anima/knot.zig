// --------------------------------------------------------------------------
// NEWSCHOOL 3: THE KNOT. A trefoil knot tube (knot_mesh.zig, 200 quads) in
// molten gold, turned and lit on ZIGGY's FPU in f32 (no f64, no libm: the
// sines come from the integer table), sorted far to near and filled by CHISEL
// TRIANGLE ops, 16 light levels a face. Behind it a synthwave sunset that is a
// REAL raster again: entry 0 rewritten every line, so the sky and its sun
// stripes run through the open borders while the knot flies through them.
// The erase is one fill of last frame's box.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const M = @import("knot_mesh.zig");
const raster = @import("raster.zig");
const grade = @import("grade.zig");
const sky = @import("knot_sky.zig");
const T = @import("timeline.zig");

const LEN = T.END - T.TORUS;
const INK: u8 = 32; // 32..47: the gold ramp, dark to bright
const CX: f32 = 200;
const CY: f32 = 140;
const FOCAL: f32 = 330;

// The gold ramp (STE levels); grade.build lights level l by light (15 = full).
const GOLD = [16][3]u8{
    .{ 1, 0, 0 },   .{ 2, 0, 0 },   .{ 3, 1, 0 },   .{ 5, 1, 0 },
    .{ 6, 2, 0 },   .{ 8, 3, 0 },   .{ 9, 4, 1 },   .{ 11, 5, 1 },
    .{ 12, 7, 1 },  .{ 13, 8, 2 },  .{ 14, 10, 2 }, .{ 15, 11, 3 },
    .{ 15, 12, 5 }, .{ 15, 13, 8 }, .{ 15, 14, 11 }, .{ 15, 15, 15 },
};

const Box = struct { x0: i16 = 0, y0: i16 = 0, x1: i16 = 0, y1: i16 = 0 };
var last: Box = .{};
var pal_key: u32 = 0xFFFF_FFFF;
var pts: [M.NV]zg.BlitVec2 = undefined;
var zs: [M.NV]f32 = undefined;
var order: [M.NQ]u16 = undefined;
var depth: [M.NQ]f32 = undefined;
var shade: [M.NQ]u8 = undefined;

pub fn enter(fb: *zg.LogicalFB, bl: *zg.Blitter) void {
    raster.use(&.{0});
    raster.timing(fb, true);
    raster.openAll();
    bl.clear(fb, 0);
    last = .{};
    pal_key = 0xFFFF_FFFF;
}

fn q16(v: i32) f32 {
    return @as(f32, @floatFromInt(v)) * (1.0 / 65536.0);
}

pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, lt: u32) void {
    const white = grade.flash(lt, LEN);
    const key = white | @as(u32, grade.beat) << 8;
    if (key != pal_key) {
        pal_key = key;
        for (0..16) |l| fb.palette[INK + l] = grade.lit(&GOLD[l], 15, white);
    }
    sky.build(lt, white);
    if (last.x1 > last.x0) bl.fill(fb, last.x0, last.y0, @intCast(last.x1 - last.x0), @intCast(last.y1 - last.y0), 0);
    const m = matrix(lt *% (5 << 22), lt *% (3 << 22) +% @as(u32, @bitCast(trig.sin(lt *% (1 << 23)) << 13)), lt *% (1 << 22));
    const zin = @as(f32, @floatFromInt(if (lt < 90) 90 - lt else 0));
    const dist: f32 = 3.0 + zin * zin * (1.0 / 300.0) + 0.4 * q16(trig.sin(lt *% (3 << 23)));
    const cx = CX + 70.0 * q16(trig.sin(lt *% (1 << 23)));
    const cy = CY + 30.0 * q16(trig.sin(lt *% (3 << 22) +% (1 << 30)));
    var box = Box{ .x0 = 400, .y0 = 280, .x1 = 0, .y1 = 0 };
    for (M.MESH.v, 0..) |v, i| {
        const x = m[0] * v[0] + m[1] * v[1] + m[2] * v[2];
        const y = m[3] * v[0] + m[4] * v[1] + m[5] * v[2];
        const z = m[6] * v[0] + m[7] * v[1] + m[8] * v[2];
        const s = FOCAL / (z + dist);
        const p = zg.BlitVec2{ .x = @intFromFloat(cx + x * s), .y = @intFromFloat(cy + y * s) };
        pts[i] = p;
        zs[i] = z;
        box = .{ .x0 = @min(box.x0, p.x), .y0 = @min(box.y0, p.y), .x1 = @max(box.x1, p.x + 1), .y1 = @max(box.y1, p.y + 1) };
    }
    const n = faces(&m);
    for (order[0..n]) |q| {
        const v = M.MESH.q[q].v;
        const c = INK + shade[q];
        bl.triangleEx(fb, pts[v[0]], pts[v[1]], pts[v[2]], c, 0, .copy);
        bl.triangleEx(fb, pts[v[0]], pts[v[2]], pts[v[3]], c, 0, .copy);
    }
    last = .{ .x0 = @max(0, box.x0), .y0 = @max(0, box.y0), .x1 = @min(400, box.x1), .y1 = @min(280, box.y1) };
}

/// The quads facing the eye, lit and sorted far to near; returns how many.
fn faces(m: *const [9]f32) usize {
    var n: usize = 0;
    for (M.MESH.q, 0..) |q, i| {
        const a = pts[q.v[0]];
        const b = pts[q.v[1]];
        const c = pts[q.v[2]];
        const cross = @as(i32, b.x - a.x) * (c.y - a.y) - @as(i32, b.y - a.y) * (c.x - a.x);
        if (cross >= 0) continue;
        // light from the upper left, towards the eye
        const nx = m[0] * q.n[0] + m[1] * q.n[1] + m[2] * q.n[2];
        const ny = m[3] * q.n[0] + m[4] * q.n[1] + m[5] * q.n[2];
        const nz = m[6] * q.n[0] + m[7] * q.n[1] + m[8] * q.n[2];
        const l = -0.45 * nx - 0.55 * ny - 0.7 * nz;
        shade[i] = @intFromFloat(@max(0.0, @min(15.0, 2.0 + l * 13.0)));
        depth[i] = zs[q.v[0]] + zs[q.v[2]];
        var j = n;
        while (j > 0 and depth[order[j - 1]] < depth[i]) : (j -= 1) order[j] = order[j - 1];
        order[j] = @intCast(i);
        n += 1;
    }
    return n;
}

fn matrix(ax: u32, ay: u32, az: u32) [9]f32 {
    const sx = q16(trig.sin(ax));
    const cx = q16(trig.cos(ax));
    const sy = q16(trig.sin(ay));
    const cy = q16(trig.cos(ay));
    const sz = q16(trig.sin(az));
    const cz = q16(trig.cos(az));
    return .{
        cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx,
        sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
        -sy,     cy * sx,                cy * cx,
    };
}
