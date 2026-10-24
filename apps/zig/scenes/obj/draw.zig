// --------------------------------------------------------------------------
// OBJ demo: the six shading modes, one plane, painter's order.
//
// Each face or edge goes to CHISEL or to the CPU (raster.zig), whichever is
// cheaper on the board: a CHISEL op costs ~800 cycles before its first pixel,
// so a face a few rows high or a short edge is drawn by the CPU, a big one by
// CHISEL. Both follow CHISEL's own pixel rules, so the choice never shows.
// Thresholds measured with apps/frame_cost.mjs on the sphere levels.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const raster = @import("raster.zig");
const fmesh = @import("fmesh.zig");
const xform = @import("xform.zig");

pub const Mode = enum(u8) { flat, glenz, wire, soft, gouraud, hidden };
pub const NAMES = [_][]const u8{ "FLAT", "GLENZ", "WIRE", "SOFT", "GOURAUD", "HIDDEN" };
pub const WIRE_INK: u8 = 201;

/// Where the work splits: a face `rows` high or less is filled by the CPU, an
/// edge `len` long or less is drawn by the CPU, the rest by CHISEL. Key C
/// cycles these so the board can be asked too; DEFAULT_SPLIT is the one
/// apps/frame_cost.mjs found cheapest over the models and sphere levels
/// (2026-10-24: FLAT ties, WIRE L3 1.01 Mc vs 1.03-1.06 for the others; its
/// model charges a CHISEL op ~400 cycles, so the board may prefer more CPU).
pub const Split = struct { rows: i32, len: i32, name: []const u8 };
pub const SPLITS = [_]Split{
    .{ .rows = -1, .len = -1, .name = "CHISEL" },
    .{ .rows = 8, .len = 16, .name = "CPU<8" },
    .{ .rows = 16, .len = 32, .name = "CPU<16" },
    .{ .rows = 24, .len = 64, .name = "CPU<24" },
    .{ .rows = 48, .len = 128, .name = "CPU<48" },
    .{ .rows = 9999, .len = 9999, .name = "CPU" },
};
pub const DEFAULT_SPLIT = 1;

pub const Ctx = struct {
    fb: *zg.LogicalFB,
    b: *zg.Blitter,
    m: *const fmesh.Mesh,
    fr: *xform.Frame,
    split: Split,

    fn target(c: Ctx) raster.Target {
        return .{ .px = c.fb.fb, .stride = c.fb.stride, .w = c.fb.fb_w, .h = c.fb.fb_h };
    }
    fn pts(c: Ctx, f: fmesh.Face) [3]raster.P {
        return .{ c.fr.pv[f.a].s, c.fr.pv[f.b].s, c.fr.pv[f.c].s };
    }
};

fn vec(p: raster.P) zg.BlitVec2 {
    return .{ .x = p[0], .y = p[1] };
}

fn rows(v: [3]raster.P) i32 {
    return @as(i32, @max(v[0][1], @max(v[1][1], v[2][1]))) - @min(v[0][1], @min(v[1][1], v[2][1]));
}

fn fillTri(c: Ctx, v: [3]raster.P, color: u8, mt: zg.Minterm) void {
    if (rows(v) <= c.split.rows) {
        if (mt == .glenz) raster.glenz(c.target(), v, color) else raster.flat(c.target(), v, color);
    } else c.b.triangleEx(c.fb, vec(v[0]), vec(v[1]), vec(v[2]), color, 0, mt);
}

fn edge(c: Ctx, a: raster.P, b: raster.P) void {
    const len = @max(@abs(@as(i32, a[0]) - b[0]), @abs(@as(i32, a[1]) - b[1]));
    if (len <= c.split.len) raster.line(c.target(), a, b, WIRE_INK) else c.b.line(c.fb, a[0], a[1], b[0], b[1], WIRE_INK, .copy);
}

pub fn draw(c: Ctx, mode: Mode) void {
    switch (mode) {
        .flat => flatLit(c, false),
        .soft => flatLit(c, true),
        .glenz => glenzAll(c),
        .wire => wireAll(c),
        .gouraud => gouraudLit(c),
        .hidden => hiddenLine(c),
    }
}

/// FLAT (CHISEL, the CPU for small faces) and SOFT (always the CPU): the faces
/// turned to the eye, far first, lit flat.
fn flatLit(c: Ctx, soft: bool) void {
    c.fr.cullSort(c.m, true, true);
    for (c.fr.recs[0..c.fr.nvis]) |r| {
        const v = [3]raster.P{ c.fr.pv[r.a].s, c.fr.pv[r.b].s, c.fr.pv[r.c].s };
        const color: u8 = @intCast(r.shade);
        if (soft) raster.soft(c.target(), v, color) else fillTri(c, v, color, .copy);
    }
}

/// GLENZ: every face ORs its own bit (face index mod 6), see-through, no cull.
/// One path for the whole frame, so the CPU never reads bytes CHISEL has just
/// written in it (that would lean on the board's wait + D$ invalidate): the
/// CPU's OR reads every pixel it writes, so CHISEL is cheaper until the faces
/// average under GLENZ_CPU_AREA pixels of the object's box (frame_cost: sphere
/// L9 2.38 Mc either way, L10 2.93 CHISEL / 2.83 CPU, L13 6.14 / 4.96). The
/// all-CHISEL and all-CPU splits force their path.
pub const GLENZ_CPU_AREA = 10; // the sphere box is ~98 px square: L8 averages 11.4 px a face, L9 8.8

fn glenzAll(c: Ctx) void {
    var cc = c;
    const box = c.fr.box;
    const area = (box[2] - box[0] + 1) * (box[3] - box[1] + 1);
    const small = area < GLENZ_CPU_AREA * @as(i32, c.m.nfaces);
    const all_cpu = c.split.rows >= SPLITS[SPLITS.len - 1].rows;
    cc.split.rows = if (all_cpu or (small and c.split.rows >= 0)) 9999 else -1;
    for (c.m.faces[0..c.m.nfaces], 0..) |f, i| {
        const bit: u8 = @as(u8, 1) << @intCast(i % 6);
        fillTri(cc, cc.pts(f), bit, .glenz);
    }
}

/// WIRE: every face's three edges, as before (shared edges drawn twice).
fn wireAll(c: Ctx) void {
    for (c.m.faces[0..c.m.nfaces]) |f| {
        const v = c.pts(f);
        edge(c, v[0], v[1]);
        edge(c, v[1], v[2]);
        edge(c, v[2], v[0]);
    }
}

/// GOURAUD: the faces turned to the eye, far first, the vertex light levels
/// interpolated across each face (palette 1..32). CPU only: CHISEL has no
/// shaded triangle.
fn gouraudLit(c: Ctx) void {
    c.fr.cullSort(c.m, true, false);
    const lev = &c.fr.lev;
    for (c.fr.recs[0..c.fr.nvis]) |r| {
        const v = [3]raster.P{ c.fr.pv[r.a].s, c.fr.pv[r.b].s, c.fr.pv[r.c].s };
        raster.gouraud(c.target(), v, .{ lev[r.a], lev[r.b], lev[r.c] }, 1, xform.GOURAUD_TOP);
    }
}

/// HIDDEN: each edge once, when a face that holds it is turned to the eye
/// (hidden-line removal on a convex model; the three here are convex).
fn hiddenLine(c: Ctx) void {
    c.fr.cullOnly(c.m);
    const vis = &c.fr.vis;
    for (c.m.edges[0..c.m.nedges]) |e| {
        const seen = vis[e.f0] or (e.f1 != fmesh.NO_FACE and vis[e.f1]);
        if (seen) edge(c, c.fr.pv[e.a].s, c.fr.pv[e.b].s);
    }
}
