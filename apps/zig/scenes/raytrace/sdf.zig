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

pub fn Sdf(comptime M: type) type {
    const T = M.T;
    const V = Vec(M);
    return struct {
        pub const NONE: u8 = 255;
        pub const MAX_STEPS = 64;
        pub const EPS = M.k(0.004); // surface hit threshold
        pub const SELF = M.k(0.03); // ray-origin lift off a surface (> EPS)
        pub const TMAX = M.k(30.0);

        pub const Sphere = struct { c: V, r: T, inv_r: T };
        pub const Hit = struct { t: T, id: u8 };

        // Index = material: 0 chrome, 1 red, 2 gold, 3 blue, 4 green.
        pub const spheres = [_]Sphere{
            sph(0.0, 1.3, 2.2, 1.3),
            sph(-3.0, 0.9, 1.0, 0.9),
            sph(3.1, 0.8, 1.6, 0.8),
            sph(-1.3, 0.5, -0.9, 0.5),
            sph(1.5, 0.45, -0.6, 0.45),
        };

        fn sph(comptime x: f64, comptime y: f64, comptime z: f64, comptime r: f64) Sphere {
            return .{ .c = V.of(M.k(x), M.k(y), M.k(z)), .r = M.k(r), .inv_r = M.k(1.0 / r) };
        }

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
            if (o.y <= 0 or d.y > -M.k(0.002)) return null;
            return M.div(o.y, -d.y);
        }
    };
}
