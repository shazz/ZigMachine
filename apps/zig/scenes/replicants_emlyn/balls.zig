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
// Their positions are pixel-verified against three.js r49's own Projector
// (codef3d_test.zig) — only the PAINTING became real rasters (rasters.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const c3 = zg.codef3d;

const CANVAS_W = 640; // new canvas(640, 480, "main")
const CANVAS_H = 480;
const CAM_Z = 800.0;
const FOV = 50.0;
const NEAR = 1.0;
const FAR = 1600.0;
const GROUP_SCALE = 60.0;
pub const ROT_STEP = 0.04;

/// myobjvert: three rings of bars along z, all at x = 0 (screen.js:45-61).
pub const POINTS = [12]c3.Vec3{
    .{ .x = 0, .y = 1, .z = -5 },
    .{ .x = 0, .y = -1, .z = -5 },
    .{ .x = 0, .y = 3, .z = 0 },
    .{ .x = 0, .y = 2, .z = 0 },
    .{ .x = 0, .y = 1, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = -1, .z = 0 },
    .{ .x = 0, .y = -2, .z = 0 },
    .{ .x = 0, .y = -3, .z = 0 },
    .{ .x = 0, .y = 1, .z = 5 },
    .{ .x = 0, .y = 0, .z = 5 },
    .{ .x = 0, .y = -1, .z = 5 },
};

// Built at run time, not comptime: the perspective matrix wants the machine's
// own @tan (musl's, as V8's is), not the compiler's constant folder.
var lens: c3.Lens = undefined;

pub fn init() void {
    lens = c3.Lens.init(CANVAS_W, CANVAS_H, FOV, NEAR, FAR);
}

/// my3d.draw()'s projection half: the visible bars, far to near.
pub fn project(rotation_x: f64, out: []c3.Particle) []c3.Particle {
    const camera = c3.Vec3{ .x = 0, .y = 0, .z = CAM_Z };
    const rotation = c3.Vec3{ .x = rotation_x, .y = 0, .z = 0 };
    return c3.projectParticles(&lens, camera, rotation, GROUP_SCALE, &POINTS, out);
}
