// The scene as a signed distance field, and sphere tracing through it.
//
// SDF: the union of five spheres, d(p) = min_i(|p - c_i| - r_i). The checker
// floor (the plane y = 0) is NOT marched: a plane's distance shrinks with the
// height of a grazing ray, which costs hundreds of steps near the horizon, and
// it has a closed form (t = y / -dy), so the tracer intersects it analytically
// and uses its distance only to bound the march.
//
// Sphere normals need no gradient: n = (p - c) * (1/r), the reciprocal being a
// compile-time constant, so shading never divides or takes a square root.
const Vec = @import("vec.zig").Vec;

/// The spheres as f64 (x, y, z, r): index = material, 0 chrome, 1 red, 2 gold, 3 blue, 4 green.
pub const SPHERES = [_][4]f64{
    .{ 0.0, 1.3, 2.2, 1.3 },
    .{ -3.0, 0.9, 1.0, 0.9 },
    .{ 3.1, 0.8, 1.6, 0.8 },
    .{ -1.3, 0.5, -0.9, 0.5 },
    .{ 1.5, 0.45, -0.6, 0.45 },
};
pub const MAX_STEPS = 64;
pub const EPS_F: f64 = 0.004; // surface hit threshold
pub const SELF_F: f64 = 0.03; // ray-origin lift off a surface (> EPS)
pub const TMAX_F: f64 = 30.0;
pub const FLOOR_DY_F: f64 = 0.002; // a ray must fall at least this steeply to meet the floor

pub fn Sdf(comptime M: type) type {
    const T = M.T;
    const V = Vec(M);
    return struct {
        pub const NONE: u8 = 255;
        pub const EPS = M.k(EPS_F);
        pub const SELF = M.k(SELF_F);
        pub const TMAX = M.k(TMAX_F);

        pub const Sphere = struct { c: V, r: T, inv_r: T };
        pub const Hit = struct { t: T, id: u8 };

        pub const spheres = blk: {
            var o: [SPHERES.len]Sphere = undefined;
            for (SPHERES, 0..) |s, i| o[i] = .{ .c = V.of(M.k(s[0]), M.k(s[1]), M.k(s[2])), .r = M.k(s[3]), .inv_r = M.k(1.0 / s[3]) };
            break :blk o;
        };

        /// Distance to the nearest sphere surface and which sphere it is.
        pub fn map(p: V) Hit {
            var best = Hit{ .t = M.k(1000.0), .id = NONE };
            inline for (spheres, 0..) |s, i| {
                const d = p.sub(s.c).len() - s.r;
                if (d < best.t) best = .{ .t = d, .id = @intCast(i) };
            }
            return best;
        }

        /// Sphere-trace o + d*t for t < tmax; Hit.id is NONE on a miss.
        pub fn march(o: V, d: V, tmax: T) Hit {
            var t: T = 0;
            var i: u32 = 0;
            while (i < MAX_STEPS) : (i += 1) {
                const m = map(o.at(d, t));
                if (m.t < EPS) return .{ .t = t, .id = m.id };
                t += m.t;
                if (t > tmax) break;
            }
            return .{ .t = t, .id = NONE };
        }

        /// Hard shadow test: does anything block o + d*t for t < TMAX?
        pub fn occluded(o: V, d: V) bool {
            var t: T = 0;
            var i: u32 = 0;
            while (i < MAX_STEPS) : (i += 1) {
                const m = map(o.at(d, t)).t;
                if (m < EPS) return true;
                t += m;
                if (t > TMAX) break;
            }
            return false;
        }

        /// Distance along o + d*t to the floor plane y = 0, or null if the ray
        /// is level/rising or starts under it.
        pub fn floorT(o: V, d: V) ?T {
            if (o.y <= 0 or d.y > -M.k(FLOOR_DY_F)) return null;
            return M.div(o.y, -d.y);
        }
    };
}
