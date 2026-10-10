// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: the Atari "Fuji" as a solid, built at COMPTIME.
//
// Three prongs, all as tall as each other: a straight central bar and two side
// fingers whose edges bend outward going down, so each finger is narrow at the
// top and flares wide at the foot (the mountain's slopes). Each prong is a 2D
// outline extruded DEPTH units each way along z, giving a front cap, a back cap
// and one side quad per outline edge. A finger's front cap is cut into ROWS
// convex quads, one per step down its curve.
//
// Model units: x right, y DOWN (screen sense), z away from the viewer; the logo
// spans x and y in -100..100. Every face carries its outward unit normal in Q14
// (16384 = 1.0), so the renderer culls and lights by rotating normals, never by
// a winding rule: the vertex order of a quad only has to go round its edge.
// Floats appear only here, and only at compile time.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ROWS = 8; // quads down one finger's front cap
pub const DEPTH = 14; // half the extrusion
const BAR_HALF = 16.0; // the central bar spans x -16..16
const ONE = 16384.0; // Q14

pub const Kind = enum(u8) { front, back, side };
pub const Face = struct { v: [4]u8, n: [3]i16, kind: Kind };

const FINGER_PTS = 2 * (ROWS + 1);
pub const NV = 2 * (4 + 2 * FINGER_PTS); // bar + two fingers, front and back
pub const NF = (1 + 1 + 4) + 2 * (2 * ROWS + FINGER_PTS);

pub const Model = struct { verts: [NV][3]i16, faces: [NF]Face };
pub const MODEL: Model = build();

/// Inner and outer edge of the RIGHT finger at t = 0 (top) .. 1 (foot). The
/// inner edge leaves a narrow slot by the bar and swings out late; the outer
/// one starts a bar's width further out and sweeps to the logo's edge.
fn innerX(t: f64) f64 {
    return 24.0 + 30.0 * std.math.pow(f64, t, 2.6);
}
fn outerX(t: f64) f64 {
    return 48.0 + 54.0 * std.math.pow(f64, t, 2.2);
}

fn rowY(k: usize) f64 {
    return -100.0 + 200.0 * @as(f64, @floatFromInt(k)) / ROWS;
}

/// The finger's outline: down the inner edge, then back up the outer one.
/// `side` is +1 for the right finger, -1 for its mirror image.
fn fingerOutline(side: f64) [FINGER_PTS][2]f64 {
    var p: [FINGER_PTS][2]f64 = undefined;
    for (0..ROWS + 1) |k| {
        const t = @as(f64, @floatFromInt(k)) / ROWS;
        p[k] = .{ side * innerX(t), rowY(k) };
        p[FINGER_PTS - 1 - k] = .{ side * outerX(t), rowY(k) };
    }
    return p;
}

/// Front-cap quads of a finger, as indices into its outline: row k joins inner
/// k, k+1 to outer k+1, k.
fn fingerQuads() [ROWS][4]usize {
    var q: [ROWS][4]usize = undefined;
    for (0..ROWS) |k| q[k] = .{ k, k + 1, FINGER_PTS - 2 - k, FINGER_PTS - 1 - k };
    return q;
}

const Builder = struct {
    m: Model = undefined,
    nv: usize = 0,
    nf: usize = 0,

    fn face(self: *Builder, v: [4]usize, n: [3]f64, kind: Kind) void {
        var f: Face = .{ .v = undefined, .n = undefined, .kind = kind };
        for (0..4) |i| f.v[i] = @intCast(v[i]);
        for (0..3) |i| f.n[i] = @intFromFloat(@round(n[i] * ONE));
        self.m.faces[self.nf] = f;
        self.nf += 1;
    }

    /// Extrude one prong: its caps (the quads), then a side per outline edge.
    fn prong(self: *Builder, pts: []const [2]f64, quads: []const [4]usize) void {
        const base = self.nv;
        const len = pts.len;
        for (pts, 0..) |p, i| {
            const x: i16 = @intFromFloat(@round(p[0]));
            const y: i16 = @intFromFloat(@round(p[1]));
            self.m.verts[base + i] = .{ x, y, -DEPTH };
            self.m.verts[base + len + i] = .{ x, y, DEPTH };
        }
        self.nv += 2 * len;
        for (quads) |q| {
            self.face(.{ base + q[0], base + q[1], base + q[2], base + q[3] }, .{ 0, 0, -1 }, .front);
            self.face(.{ base + len + q[0], base + len + q[1], base + len + q[2], base + len + q[3] }, .{ 0, 0, 1 }, .back);
        }
        // Shoelace with y down: positive = clockwise on screen, and then an
        // edge (dx, dy) faces out along (dy, -dx).
        var area: f64 = 0;
        for (0..len) |i| {
            const a = pts[i];
            const b = pts[(i + 1) % len];
            area += a[0] * b[1] - b[0] * a[1];
        }
        const s: f64 = if (area > 0) 1 else -1;
        for (0..len) |i| {
            const j = (i + 1) % len;
            const dx = s * (pts[j][0] - pts[i][0]);
            const dy = s * (pts[j][1] - pts[i][1]);
            const l = @sqrt(dx * dx + dy * dy);
            self.face(.{ base + i, base + j, base + len + j, base + len + i }, .{ dy / l, -dx / l, 0 }, .side);
        }
    }
};

fn build() Model {
    @setEvalBranchQuota(200_000);
    var b: Builder = .{};
    const bar = [4][2]f64{ .{ -BAR_HALF, -100 }, .{ BAR_HALF, -100 }, .{ BAR_HALF, 100 }, .{ -BAR_HALF, 100 } };
    b.prong(&bar, &.{.{ 0, 1, 2, 3 }});
    const quads = fingerQuads();
    b.prong(&fingerOutline(1), &quads);
    b.prong(&fingerOutline(-1), &quads);
    std.debug.assert(b.nv == NV and b.nf == NF);
    return b.m;
}

test "every face's normal is a unit vector and points away from the solid" {
    for (MODEL.faces) |f| {
        const n = f.n;
        const len2 = @as(i64, n[0]) * n[0] + @as(i64, n[1]) * n[1] + @as(i64, n[2]) * n[2];
        try std.testing.expect(@abs(len2 - 16384 * 16384) < 16384 * 8);
        if (f.kind != .side) continue;
        // An outward side normal points away from its own edge's prong centre
        // line: right of the bar for x > 0 means n.x >= 0 on the outer edges.
        const v = MODEL.verts[f.v[0]];
        if (n[0] != 0 and @abs(v[0]) > 60 and v[1] > 0) try std.testing.expect((n[0] > 0) == (v[0] > 0));
    }
}
