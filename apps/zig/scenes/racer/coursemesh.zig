// --------------------------------------------------------------------------
// RACER: the course select's turning 3D model of a course (R82 board batch, item 9: the mechanic of the 32X course
// select, in our own look). The track select loads nothing while its cursor moves (preview.zig), so the model is BAKED
// at the library scan, when every track is parsed once anyway, into a few hundred bytes a track:
//   - a height field of N x N cells over the racing line's box (grown by a quarter, made square): each cell keeps the
//     face whose centre falls in it with the biggest ground area (the terrain, the road, a lake; never a wall), as its
//     ramp (one of MAXR slots, their RGB kept) and light, and that face's mean height (on the cells' own scale);
//   - the racing line, PTS points (x, y, z in 1/16 cells).
// `polys` turns it about its centre, tilts it toward the eye and projects it (integers, the 1,024-step sine table): a
// quad a cell (its corners the mean of the cells around them, lit one level up or down by its slope) and a ribbon a line
// step, each with a depth key for the frame's painter sort. coursedraw.zig pushes them into the frame. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const fx = @import("fx.zig");
const trk = @import("trk.zig");

pub const N = 12;
pub const PTS = 32;
pub const MAXR = 12; // ramp slots: palette entries 16 .. 16 + 8 * MAXR (off the car ramps 12..18)
pub const EMPTY: u8 = 0xFF;

pub const Mesh = struct {
    cell: [N * N]u8 = @splat(EMPTY), // slot << 3 | light, or EMPTY
    h: [N * N]u8 = @splat(0),
    line: [PTS][3]u8 = @splat(.{ 0, 0, 0 }),
    n: u8 = 0, // line points
    ramps: [MAXR][3]u8 = @splat(.{ 0, 0, 0 }), // the slots' RGB (the track's palette block)
    nr: u8 = 0,
    mid: u8 = 128, // the filled cells' mean height: the model turns about it
};

const Box = struct { x0: i32, z0: i32, size: i32, y0: i32 }; // Q7

fn box(t: *const trk.Track) Box {
    var lo = [2]i32{ std.math.maxInt(i32), std.math.maxInt(i32) };
    var hi = [2]i32{ std.math.minInt(i32), std.math.minInt(i32) };
    for (t.line) |s| for ([2]usize{ 0, 2 }, 0..) |c, i| {
        lo[i] = @min(lo[i], s.pos[c] >> 9);
        hi[i] = @max(hi[i], s.pos[c] >> 9);
    };
    const size = @max(@max(hi[0] - lo[0], hi[1] - lo[1]), 64) * 5 / 4;
    const cx = (lo[0] + hi[0]) >> 1;
    const cz = (lo[1] + hi[1]) >> 1;
    var y0: i32 = std.math.maxInt(i32);
    for (t.line) |s| y0 = @min(y0, s.pos[1] >> 9);
    return .{ .x0 = cx - size / 2, .z0 = cz - size / 2, .size = size, .y0 = y0 - size / 32 };
}

/// A height on the x / z scale (1/16 of a cell), from a little under the line's lowest point; clamped to 0..255.
fn hOf(b: Box, y: i32) u8 {
    return @intCast(std.math.clamp(@divTrunc((y - b.y0) * N * 16, b.size), 0, 255));
}

fn slotOf(m: *Mesh, t: *const trk.Track, ramp: usize, ids: *[MAXR]u8) ?u8 {
    for (ids[0..m.nr], 0..) |r, i| if (r == ramp) return @intCast(i);
    if (m.nr == MAXR or ramp >= t.palette.len) return null; // a 13th ramp: that cell stays empty
    ids[m.nr] = @intCast(ramp);
    m.ramps[m.nr] = t.palette[ramp][0..3].*;
    m.nr += 1;
    return m.nr - 1;
}

/// The model of a parsed track.
pub fn bake(t: *const trk.Track) Mesh {
    var m = Mesh{};
    if (t.line.len < 2) return m;
    const b = box(t);
    var best: [N * N]i64 = @splat(0);
    var ids: [MAXR]u8 = undefined;
    for (t.faces) |*f| {
        if (f.colour < 16 or f.nv < 3) continue;
        var c = [3]i64{ 0, 0, 0 };
        for (f.v[0..f.nv]) |id| for (0..3) |k| {
            c[k] += t.verts[id][k];
        };
        const cx = @divTrunc(c[0], f.nv) - b.x0;
        const cz = @divTrunc(c[2], f.nv) - b.z0;
        if (cx < 0 or cz < 0 or cx >= b.size or cz >= b.size) continue;
        const a = t.verts[f.v[0]];
        const p = t.verts[f.v[1]];
        const q = t.verts[f.v[2]];
        const area = @abs((@as(i64, p[0]) - a[0]) * (q[2] - a[2]) - (@as(i64, p[2]) - a[2]) * (q[0] - a[0]));
        const i: usize = @intCast(@divTrunc(cz * N, b.size) * N + @divTrunc(cx * N, b.size));
        if (area <= best[i]) continue;
        const slot = slotOf(&m, t, (f.colour - 16) / 8, &ids) orelse continue;
        best[i] = @intCast(area);
        m.cell[i] = slot << 3 | ((f.colour - 16) & 7);
        m.h[i] = hOf(b, @intCast(@divTrunc(c[1], f.nv)));
    }
    m.mid = mean(&m);
    m.n = PTS;
    for (&m.line, 0..) |*o, k| {
        const s = t.line[k * t.line.len / PTS].pos;
        o.* = .{
            @intCast(std.math.clamp(@divTrunc(((s[0] >> 9) - b.x0) * N * 16, b.size), 0, N * 16)),
            hOf(b, s[1] >> 9),
            @intCast(std.math.clamp(@divTrunc(((s[2] >> 9) - b.z0) * N * 16, b.size), 0, N * 16)),
        };
    }
    return m;
}

fn mean(m: *const Mesh) u8 {
    var sum: u32 = 0;
    var n: u32 = 0;
    for (m.cell, m.h) |c, h| if (c != EMPTY) {
        sum += h;
        n += 1;
    };
    return if (n == 0) 128 else @intCast(sum / n);
}

pub const Poly = struct { x: [4]i16, y: [4]i16, depth: i32, colour: u8 };
pub const MAXP = N * N + PTS;
pub const CX: i32 = 160;
pub const CY: i32 = 70;
const F: i32 = 380; // the projection's focal length (pixels)
const DIST: i32 = 30000; // the eye's distance from the centre (model units: a cell is 1,024)
const LIFT: i32 = 96; // a height level in model units: x / z's 64, the relief raised by half
const PITCH: u32 = 0x0E00_0000; // ~20 degrees down: the whole course fits the band over the info panel

/// Model point (x, z in 1/16 cells, y a height level about `mid`) turned by `turn`, tilted and projected; the depth in model units.
pub fn project(x: i32, y: i32, z: i32, turn: u32) struct { sx: i32, sy: i32, depth: i32 } {
    const ux = (x - N * 8) * 4;
    const uz = (z - N * 8) * 4;
    const c = fx.cos(turn);
    const s = fx.sin(turn);
    const xr = fx.mulsh16(ux << 4, c) - fx.mulsh16(uz << 4, s);
    const zr = fx.mulsh16(ux << 4, s) + fx.mulsh16(uz << 4, c);
    const yy = y * LIFT;
    const cp = fx.cos(PITCH);
    const sp = fx.sin(PITCH);
    const up = fx.mulsh16(yy, cp) + fx.mulsh16(zr, sp);
    const depth = DIST + fx.mulsh16(zr, cp) - fx.mulsh16(yy, sp);
    return .{ .sx = CX + @divTrunc(xr * F, depth), .sy = CY - @divTrunc(up * F, depth), .depth = depth };
}

/// The height at grid corner (i, j): the mean of the filled cells around it (0 with none).
fn corner(m: *const Mesh, i: usize, j: usize) i32 {
    var sum: i32 = 0;
    var n: i32 = 0;
    for ([2]usize{ 0, 1 }) |di| for ([2]usize{ 0, 1 }) |dj| {
        if (i + di == 0 or j + dj == 0 or i + di > N or j + dj > N) continue;
        const k = (j + dj - 1) * N + (i + di - 1);
        if (m.cell[k] == EMPTY) continue;
        sum += m.h[k];
        n += 1;
    };
    return if (n == 0) 0 else @divTrunc(sum, n);
}

/// The model's polygons at turn `turn` into `out` (unsorted: the frame's keys sort them): the cells, then the line.
pub fn polys(m: *const Mesh, turn: u32, out: *[MAXP]Poly) []Poly {
    var n: usize = 0;
    for (0..N) |j| for (0..N) |i| {
        const k = j * N + i;
        if (m.cell[k] == EMPTY) continue;
        const h = [4]i32{ corner(m, i, j), corner(m, i + 1, j), corner(m, i + 1, j + 1), corner(m, i, j + 1) };
        const slope = std.math.clamp(@divTrunc(h[0] + h[3] - h[1] - h[2], 16), -2, 2);
        const light: i32 = std.math.clamp(@as(i32, m.cell[k] & 7) + slope, 0, 7);
        var p = Poly{ .x = undefined, .y = undefined, .depth = 0, .colour = @intCast(16 + @as(i32, m.cell[k] >> 3) * 8 + light) };
        const xs = [4]i32{ 0, 16, 16, 0 };
        const zs = [4]i32{ 0, 0, 16, 16 };
        for (0..4) |c| {
            const q = project(@as(i32, @intCast(i)) * 16 + xs[c], h[c] - m.mid, @as(i32, @intCast(j)) * 16 + zs[c], turn);
            p.x[c] = @intCast(std.math.clamp(q.sx, -1000, 1000));
            p.y[c] = @intCast(std.math.clamp(q.sy, -1000, 1000));
            p.depth += q.depth;
        }
        p.depth >>= 2;
        out[n] = p;
        n += 1;
    };
    return out[0..n];
}

/// The racing line as a ribbon (a quad a step, `colour`, a little nearer than the ground under it) into `out`.
pub fn ribbon(m: *const Mesh, turn: u32, colour: u8, out: []Poly) []Poly {
    var n: usize = 0;
    for (0..m.n) |k| {
        if (n == out.len) break;
        const a = m.line[k];
        const b = m.line[(k + 1) % m.n];
        const dx: i32 = @as(i32, b[0]) - a[0];
        const dz: i32 = @as(i32, b[2]) - a[2];
        const len: i32 = @max(@as(i32, @intCast(std.math.sqrt(@as(u32, @intCast(dx * dx + dz * dz))))), 1);
        const w = [2]i32{ @divTrunc(-dz * 3, len), @divTrunc(dx * 3, len) }; // a road ~6/16 of a cell wide
        var p = Poly{ .x = undefined, .y = undefined, .depth = 0, .colour = colour };
        const pts = [4][3]i32{ .{ a[0] - w[0], a[1], a[2] - w[1] }, .{ a[0] + w[0], a[1], a[2] + w[1] }, .{ b[0] + w[0], b[1], b[2] + w[1] }, .{ b[0] - w[0], b[1], b[2] - w[1] } };
        for (pts, 0..) |q, c| {
            const s = project(q[0], q[1] + 2 - m.mid, q[2], turn);
            p.x[c] = @intCast(std.math.clamp(s.sx, -1000, 1000));
            p.y[c] = @intCast(std.math.clamp(s.sy, -1000, 1000));
            p.depth += s.depth;
        }
        p.depth = (p.depth >> 2) - 200; // drawn over the cell it crosses
        out[n] = p;
        n += 1;
    }
    return out[0..n];
}
