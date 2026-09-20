// --------------------------------------------------------------------------
// prototypes/codef/417/lib/obj.js — the glenz solid and the vertex sets the
// TweenMax chain morphs it through, verbatim.
//
// 14 vertices: 8 box corners plus SIX face-centre vertices (0, 5, 8, 11, 12,
// 13), so each of the box's faces is four triangles fanned from its middle.
// Pushing a face centre past its face plane turns that face into a pyramid,
// which is the whole difference between the sets below. Every one of them is
// convex, which is why a covered pixel is exactly two faces deep.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const c3 = zg.zig3d;
const A = @import("assets.zig");
const Vec3 = c3.Vec3;

fn v(x: f64, y: f64, z: f64) Vec3 {
    return .{ .x = x, .y = y, .z = z };
}

/// myobjvert[1] — a plain cube: every face centre sits ON its face plane.
pub const CUBE = [14]Vec3{
    v(0, 0, 150),      v(-150, 150, 150),  v(150, 150, 150),   v(150, -150, 150),
    v(-150, -150, 150), v(150, 0, 0),      v(150, 150, -150),  v(150, -150, -150),
    v(-150, 0, 0),     v(-150, 150, -150), v(-150, -150, -150), v(0, 0, -150),
    v(0, 150, 0),      v(0, -150, 0),
};

/// myobjvert[0] — a flat slab (y = +-50) with pyramids on +-x and +-z.
pub const SLAB = [14]Vec3{
    v(0, 0, 200),     v(-150, 50, 150),  v(150, 50, 150),   v(150, -50, 150),
    v(-150, -50, 150), v(200, 0, 0),     v(150, 50, -150),  v(150, -50, -150),
    v(-200, 0, 0),    v(-150, 50, -150), v(-150, -50, -150), v(0, 0, -200),
    v(0, 50, 0),      v(0, -50, 0),
};

/// myobjvert[3] — the cube with a pyramid raised on all six faces.
pub const SPIKE = [14]Vec3{
    v(0, 0, 200),      v(-150, 150, 150),  v(150, 150, 150),   v(150, -150, 150),
    v(-150, -150, 150), v(200, 0, 0),      v(150, 150, -150),  v(150, -150, -150),
    v(-200, 0, 0),     v(-150, 150, -150), v(-150, -150, -150), v(0, 0, -200),
    v(0, 200, 0),      v(0, -200, 0),
};

/// myobjvert[4] — the same cube at a third the size.
pub const SMALL = [14]Vec3{
    v(0, 0, 50),    v(-50, 50, 50),  v(50, 50, 50),   v(50, -50, 50),
    v(-50, -50, 50), v(50, 0, 0),    v(50, 50, -50),  v(50, -50, -50),
    v(-50, 0, 0),   v(-50, 50, -50), v(-50, -50, -50), v(0, 0, -50),
    v(0, 50, 0),    v(0, -50, 0),
};

const R = A.GLENZ_R; // col1 = 0xaa0011
const W = A.GLENZ_W; // col2 = 0xffffff

fn f(a: u16, b: u16, c: u16, ink: u8) c3.Face {
    return .{ .v = .{ a, b, c, 0 }, .n = 3, .ink = ink };
}

/// myobj: 24 triangles, alternating col1/col2 exactly as obj.js lists them.
pub const FACES = [24]c3.Face{
    f(0, 2, 1, R),   f(0, 3, 2, W),   f(0, 4, 3, R),   f(0, 1, 4, W),
    f(5, 6, 2, W),   f(5, 7, 6, R),   f(5, 3, 7, W),   f(5, 2, 3, R),
    f(8, 1, 9, W),   f(8, 9, 10, R),  f(8, 10, 4, W),  f(8, 4, 1, R),
    f(11, 6, 7, W),  f(11, 7, 10, R), f(11, 10, 9, W), f(11, 9, 6, R),
    f(12, 1, 2, W),  f(12, 2, 6, R),  f(12, 6, 9, W),  f(12, 9, 1, R),
    f(13, 7, 3, R),  f(13, 10, 7, W), f(13, 4, 10, R), f(13, 3, 4, W),
};

/// tween3d() (screen.js:200-214): four 1 s linear morphs at delay 5/10/15/20,
/// re-armed by onComplete, so the cycle is 21 s. The two objects walk the same
/// four sets in a different order.
pub const Stage = struct { at: f32, from: *const [14]Vec3, to: *const [14]Vec3 };
pub const CYCLE: f32 = 21.0;

pub const MORPH1 = [4]Stage{
    .{ .at = 5, .from = &CUBE, .to = &SLAB },
    .{ .at = 10, .from = &SLAB, .to = &SMALL },
    .{ .at = 15, .from = &SMALL, .to = &SPIKE },
    .{ .at = 20, .from = &SPIKE, .to = &CUBE },
};

pub const MORPH2 = [4]Stage{
    .{ .at = 5, .from = &CUBE, .to = &SPIKE },
    .{ .at = 10, .from = &SPIKE, .to = &SLAB },
    .{ .at = 15, .from = &SLAB, .to = &SMALL },
    .{ .at = 20, .from = &SMALL, .to = &CUBE },
};

/// Where a 21 s cycle has the vertices at time `t` (seconds since tween3d()).
pub fn morph(stages: *const [4]Stage, t: f32, out: *[14]Vec3) void {
    var from: *const [14]Vec3 = stages[0].from;
    var to: *const [14]Vec3 = stages[0].from;
    var k: f64 = 0;
    for (stages) |s| {
        if (t < s.at) break;
        from = s.from;
        to = s.to;
        k = @min(1.0, @as(f64, t - s.at)); // Linear.easeNone over 1 s
    }
    for (out, from, to) |*o, a, b| o.* = .{
        .x = a.x + (b.x - a.x) * k,
        .y = a.y + (b.y - a.y) * k,
        .z = a.z + (b.z - a.z) * k,
    };
}
