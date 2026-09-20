// --------------------------------------------------------------------------
// One of the screen's two glenz objects: three.js r49's projector (via
// zg.zig3d) feeding the BLITTER's OR minterm.
//
// THE INTERLACE. go() (screen.js:293-296) composites the two 352x352 3D
// canvases into the panel in 2-row bands, obj1 at 171+u and obj2 at 173+u for
// u = 0,4,8,...  On the 1x grid (a 1x row is 2x rows 2r+1, 2r+2) that is:
// object 1's canvas row s lands on panel row s for EVEN s only, object 2's on
// panel row s+1 for even s — i.e. each object is shown on alternate scanlines,
// the classic Amiga two-objects-through-each-other trick. So no off-screen
// canvas is needed: each object is drawn straight into the plane through a
// HALFTONE of alternating full rows, with BG_COLOR 0, because 0 OR dest leaves
// the rows it does not own untouched.
//
// THE GLENZ. MT_OR_BC ORs a face's ink into the destination, which is why the
// panel is index 0 and a face's ink is one bit: 1 (col1) | 2 (col2) = 3, the
// overlap. That is the hardware technique the CODEF remake is imitating with
// canvas globalAlpha, and it is what the Amiga did. Its one cost is that OR is
// symmetric, so red-over-white and white-over-red land on the same index (see
// GLENZ_RW in assets.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const c3 = zg.zig3d;
const Blitter = zg.Blitter;
const Vec2 = zg.BlitVec2;
const LogicalFB = zg.LogicalFB;
const obj = @import("obj.zig");

const Vec3 = c3.Vec3;

/// new codef3D(mycanvas3d, 900, 40, 1, 3000) on a 352x352 canvas, halved: the
/// aspect is 1 either way, so the projection matrix is identical and only the
/// half-width changes.
pub const CANVAS = 176;
pub const CAMERA = Vec3{ .x = 0, .y = 0, .z = 900 };
pub const FOV = 40.0;
pub const NEAR = 1.0;
pub const FAR = 3000.0;

/// doubleSided, no overdraw — my3d.faces(myobjvert[1], myobj, true, false).
const OPTS = c3.Options{ .double_sided = true, .overdraw = false };

// Shared scratch: the two objects are projected one after the other, and this
// keeps 1.5 KB out of every Demo (and out of the cart's data segment budget).
var screen_scratch: [14]c3.Screen = undefined;
var poly_scratch: [24]c3.Poly = undefined;

/// Rows of the 16x16 halftone an object owns. `odd` selects plane rows 1,3,5...
fn stripes(comptime odd: bool) [16]u16 {
    var p: [16]u16 = undefined;
    for (&p, 0..) |*row, i| row.* = if ((i & 1 == 1) == odd) 0xFFFF else 0;
    return p;
}
pub const ODD_ROWS = stripes(true);
pub const EVEN_ROWS = stripes(false);

fn round(v: f64) i16 {
    return @intFromFloat(@round(@max(-4096.0, @min(4096.0, v))));
}

pub const Glenz = struct {
    verts: [14]Vec3,
    centroids: [24]Vec3,
    mesh: c3.Mesh,
    rotation: Vec3,
    step: Vec3,
    stages: *const [4]obj.Stage,
    left: i16, // plane column the canvas's column 0 lands on
    top: i16, // plane row the canvas's row 0 lands on
    halftone: [16]u16,

    pub fn init(self: *Glenz, stages: *const [4]obj.Stage, step: Vec3, left: i16, top: i16, halftone: [16]u16) void {
        self.verts = obj.CUBE;
        self.centroids = undefined;
        // faces() computes the centroids and the bounding sphere ONCE, from
        // myobjvert[1]; the tween then moves the vertices and never recomputes
        // either. Building from CUBE and re-pointing the slice keeps that.
        self.mesh = c3.build(&obj.CUBE, &obj.FACES, &self.centroids);
        self.mesh.verts = &self.verts;
        self.rotation = .{ .x = 0, .y = 0, .z = 0 };
        self.step = step;
        self.stages = stages;
        self.left = left;
        self.top = top;
        self.halftone = halftone;
    }

    /// go() turns the group, then computes normals, then draws. `t` is seconds
    /// since tween3d() armed the chain.
    pub fn update(self: *Glenz, t: f32) void {
        self.rotation.x += self.step.x;
        self.rotation.y += self.step.y;
        self.rotation.z += self.step.z;
        obj.morph(self.stages, t, &self.verts);
    }

    pub fn draw(self: *Glenz, fb: *LogicalFB, bl: *Blitter, lens: *const c3.Lens) void {
        const origin = Vec3{ .x = 0, .y = 0, .z = 0 };
        const polys = c3.projectEx(lens, CAMERA, origin, self.rotation, &self.mesh, &screen_scratch, &poly_scratch, OPTS);
        bl.setHalftone(self.halftone);
        for (polys) |p| {
            bl.triangleEx(fb, self.at(p, 0), self.at(p, 1), self.at(p, 2), p.ink, 0, .glenz);
        }
        bl.clearHalftone();
    }

    /// Canvas pixels to plane pixels. Clamped before the cast: the object
    /// never reaches 73 px from the canvas centre, but @intFromFloat on an
    /// out-of-range float is illegal, not merely wrong.
    fn at(self: *const Glenz, p: c3.Poly, i: usize) Vec2 {
        return .{ .x = self.left + round(p.pts[i][0]), .y = self.top + round(p.pts[i][1]) };
    }
};
