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

/// A face this many rows high or less is filled by the CPU.
pub const TRI_CPU_ROWS: i32 = 24;
/// An edge this many pixels long or less is drawn by the CPU.
pub const LINE_CPU_LEN: i32 = 64;

pub const Ctx = struct {
    fb: *zg.LogicalFB,
    b: *zg.Blitter,
    m: *const fmesh.Mesh,
    fr: *xform.Frame,

    fn target(c: Ctx) raster.Target {
        return .{ .px = c.fb.fb, .stride = c.fb.stride, .w = c.fb.fb_w, .h = c.fb.fb_h };
    }
    fn pts(c: Ctx, f: fmesh.Face) [3]raster.P {
        return .{ c.fr.scr[f.a], c.fr.scr[f.b], c.fr.scr[f.c] };
    }
};

fn vec(p: raster.P) zg.BlitVec2 {
    return .{ .x = p[0], .y = p[1] };
}

fn rows(v: [3]raster.P) i32 {
    return @as(i32, @max(v[0][1], @max(v[1][1], v[2][1]))) - @min(v[0][1], @min(v[1][1], v[2][1]));
}

fn fillTri(c: Ctx, v: [3]raster.P, color: u8, mt: zg.Minterm) void {
    if (rows(v) <= TRI_CPU_ROWS) {
        if (mt == .glenz) raster.glenz(c.target(), v, color) else raster.flat(c.target(), v, color);
    } else c.b.triangleEx(c.fb, vec(v[0]), vec(v[1]), vec(v[2]), color, 0, mt);
}

fn edge(c: Ctx, a: raster.P, b: raster.P) void {
    const len = @max(@abs(@as(i32, a[0]) - b[0]), @abs(@as(i32, a[1]) - b[1]));
    if (len <= LINE_CPU_LEN) raster.line(c.target(), a, b, WIRE_INK) else c.b.line(c.fb, a[0], a[1], b[0], b[1], WIRE_INK, .copy);
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
    c.fr.cullSort(c.m, true);
    for (c.fr.order[0..c.fr.nvis]) |f| {
        const color: u8 = 1 + c.fr.flatLevel(c.m, f);
        const v = c.pts(c.m.faces[f]);
        if (soft) raster.soft(c.target(), v, color) else fillTri(c, v, color, .copy);
    }
}

/// GLENZ: every face ORs its own bit (face index mod 6), see-through, no cull.
fn glenzAll(c: Ctx) void {
    for (c.m.faces[0..c.m.nfaces], 0..) |f, i| {
        const bit: u8 = @as(u8, 1) << @intCast(i % 6);
        fillTri(c, c.pts(f), bit, .glenz);
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
    c.fr.cullSort(c.m, true);
    const lev = &c.fr.lev;
    for (c.fr.order[0..c.fr.nvis]) |fi| {
        const f = c.m.faces[fi];
        raster.gouraud(c.target(), c.pts(f), .{ lev[f.a], lev[f.b], lev[f.c] }, 1, xform.GOURAUD_TOP);
    }
}

/// HIDDEN: each edge once, when a face that holds it is turned to the eye
/// (hidden-line removal on a convex model; the three here are convex).
fn hiddenLine(c: Ctx) void {
    c.fr.cullOnly(c.m);
    const vis = &c.fr.vis;
    for (c.m.edges[0..c.m.nedges]) |e| {
        const seen = vis[e.f0] or (e.f1 != fmesh.NO_FACE and vis[e.f1]);
        if (seen) edge(c, c.fr.scr[e.a], c.fr.scr[e.b]);
    }
}
