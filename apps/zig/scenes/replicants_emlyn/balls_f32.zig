// --------------------------------------------------------------------------
// The vectorballs: twelve THREE.Particles carrying bar.png as their
// ParticleCanvasMaterial program (screen.js:43-61, 70-72, 96-98).
//
//   my3d = new codef3D(mycanvas, 800, 50, 1, 1600)    camZ, fov, near, far
//   my3d.vectorball_img(myobjvert, ball)              all twelve use ball[0]
//   group.scale.x = y = z = 60
//   group.rotation.x += 0.04                          every frame, before draw
//
// Every particle has x = 0, so the whole set turns about the camera's x axis in
// the plane x = 0 and every bar lands on the canvas midline: what each one
// contributes is a canvas y and a scale, which is exactly what a raster needs.
//
// THIS is replicants_emlyn_f32's projection: three.js r49's Projector math
// (zig3d.projectParticles, pixel-verified in zig3d_test.zig) written out for
// points on the x = 0 plane, in f32, for the FPU test. The default cart does the
// same in integers (balls_fixed.zig), from the POINTS and lens declared here.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const c3 = zg.zig3d;

pub const CANVAS_W = 640; // new canvas(640, 480, "main")
pub const CANVAS_H = 480;
pub const CAM_Z = 800;
pub const FOV = 50.0;
pub const NEAR = 1;
pub const FAR = 1600;
pub const GROUP_SCALE = 60;
pub const ROT_STEP = 0.04;
const HALF_H: f32 = CANVAS_H / 2;

/// myobjvert: three rings of bars along z, all at x = 0 (screen.js:45-61),
/// as (y, z) pairs.
pub const POINTS = [12][2]i32{
    .{ 1, -5 }, .{ -1, -5 },
    .{ 3, 0 },  .{ 2, 0 },
    .{ 1, 0 },  .{ 0, 0 },
    .{ -1, 0 }, .{ -2, 0 },
    .{ -3, 0 }, .{ 1, 5 },
    .{ 0, 5 },  .{ -1, 5 },
};

/// A projected bar: its canvas y, its program's vertical scale, its clip z.
pub const Particle = struct { y: f32, sy: f32, z: f32 };

/// The perspective matrix three.js builds, by the Lens zig3d uses, at run time
/// (the machine's own @tan, as V8's is). Only the x = 0 plane's entries matter.
pub fn lens() c3.Lens {
    return c3.Lens.init(CANVAS_W, CANVAS_H, FOV, NEAR, FAR);
}

var p5: f32 = 0;
var p10: f32 = 0;
var p14: f32 = 0;

pub fn init() void {
    const l = lens();
    p5 = l.projection.e[5];
    p10 = l.projection.e[10];
    p14 = l.projection.e[14];
}

/// my3d.draw()'s projection half: the visible bars, far to near.
pub fn project(rotation_x: f32, out: []Particle) []Particle {
    const s = @sin(rotation_x);
    const c = @cos(rotation_x);
    var n: usize = 0;
    for (POINTS) |pt| {
        const py: f32 = @floatFromInt(pt[0]);
        const pz: f32 = @floatFromInt(pt[1]);
        // group.rotation.x, then Matrix4.scale(60): the particle's world position
        const y = GROUP_SCALE * (py * c - pz * s);
        const z = GROUP_SCALE * (py * s + pz * c);
        // the view is the camera's translation; clip = projection * view * world
        const ey = p5 * y;
        const ez = p10 * (z - CAM_Z) + p14;
        const ew = CAM_Z - z;
        const zc = ez / ew;
        if (!(zc > 0 and zc < 1)) continue;
        const ay = ey / ew * HALF_H;
        const sy = @abs(ey / ew - (ey + p5) / ew) * HALF_H;
        // the renderer's box is sy tall, so a bar whose centre leaves is dropped
        if (ay + sy < -HALF_H or ay - sy > HALF_H) continue;
        out[n] = .{ .y = -ay + HALF_H, .sy = sy, .z = zc };
        n += 1;
    }
    std.sort.insertion(Particle, out[0..n], {}, farther);
    return out[0..n];
}

fn farther(_: void, a: Particle, b: Particle) bool {
    return b.z - a.z < 0;
}
