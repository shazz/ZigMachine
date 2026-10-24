// The tracer: one primary ray per pixel, then at most one hard-shadow ray and
// (for the chrome sphere) one reflection ray, each shaded to a P.Shade (a ramp
// and its 0..256 intensities) that P.index dithers to a palette index. Generic
// over the number back-end, so fixed-point and f32 carts are the same source.
// No float appears here in the fixed-point build: constants go through M.k at
// compile time, everything else through M's operators.
//
// centre() is the one-sample picture both carts draw first. sample() is the same
// ray through a sub-pixel offset under a given light direction, for the f32
// cart's refinement passes (refine.zig), which average the Shades.
const Vec = @import("vec.zig").Vec;
const Sdf = @import("sdf.zig").Sdf;
const P = @import("palette.zig");

pub const IMG_W: u32 = 320;
pub const IMG_H: u32 = 176; // rows 176..199 are the HUD
const HORIZON_ROW: i32 = 62;

pub const Stats = struct { rays: u32 };

/// Toward the light, unnormalised: up, left and behind the camera.
pub const SUN_DIR = [3]f64{ -0.6, 0.55, -0.35 };

pub fn Tracer(comptime M: type) type {
    const T = M.T;
    const V = Vec(M);
    const S = Sdf(M);
    return struct {
        const CAM = V.of(M.k(0.0), M.k(1.7), M.k(-6.5));
        const PIXEL = M.k(1.0 / 240.0); // image-plane units per pixel (focal length 1)
        const AMB = M.k(0.16);
        // Unit vector TOWARD the light.
        const LIGHT = blk: {
            const x = SUN_DIR[0];
            const y = SUN_DIR[1];
            const z = SUN_DIR[2];
            const n = @sqrt(x * x + y * y + z * z);
            break :blk V.of(M.k(x / n), M.k(y / n), M.k(z / n));
        };

        pub const Vec3 = V;

        /// The pixel at (x, y), not yet dithered (P.index); counts every ray.
        pub fn centre(st: *Stats, x: u32, y: u32) P.Shade {
            const u = M.mul(M.fromInt(@as(i32, @intCast(x)) - 160), PIXEL);
            const v = M.mul(M.fromInt(HORIZON_ROW - @as(i32, @intCast(y))), PIXEL);
            return trace(st, CAM, V.of(u, v, M.ONE).unit(), LIGHT, 0);
        }

        /// The ray through (x + jx, y + jy) lit from `light`, not yet dithered.
        pub fn sample(st: *Stats, x: u32, y: u32, jx: T, jy: T, light: V) P.Shade {
            const u = M.mul(M.fromInt(@as(i32, @intCast(x)) - 160) + jx, PIXEL);
            const v = M.mul(M.fromInt(HORIZON_ROW - @as(i32, @intCast(y))) - jy, PIXEL);
            return trace(st, CAM, V.of(u, v, M.ONE).unit(), light, 0);
        }

        fn trace(st: *Stats, o: V, d: V, light: V, depth: u8) P.Shade {
            st.rays += 1;
            const tf = S.floorT(o, d);
            const tmax = if (tf) |f| @min(f, S.TMAX) else S.TMAX;
            const h = S.march(o, d, tmax);
            if (h.id != S.NONE) return sphere(st, o, d, h, light, depth);
            if (tf) |f| if (f < S.TMAX) return floor(st, o.at(d, f), f, light);
            return sky(d);
        }

        fn sky(d: V) P.Shade {
            return .{ .cls = P.CLS_SKY, .q = @intCast(M.toQ8(M.mul(d.y, M.k(2.2)))), .fog = 0 };
        }

        fn floor(st: *Stats, p: V, t: T, light: V) P.Shade {
            const tone: u8 = @intCast((M.toInt(p.x) + M.toInt(p.z)) & 1);
            st.rays += 1;
            const lit = !S.occluded(V.of(p.x, S.SELF, p.z), light);
            const fog = M.toQ8(M.mul(t, M.k(1.0 / 30.0)));
            return .{ .cls = P.CLS_FLOOR + tone, .q = if (lit) 256 else 80, .fog = @intCast(fog) };
        }

        fn sphere(st: *Stats, o: V, d: V, h: S.Hit, light: V, depth: u8) P.Shade {
            const s = S.spheres[h.id];
            const p = o.at(d, h.t);
            const n = p.sub(s.c).scale(s.inv_r);
            const po = p.add(n.scale(S.SELF));
            if (h.id == 0 and depth == 0) {
                const r = d.sub(n.scale(M.mul(d.dot(n), M.k(2.0))));
                return trace(st, po, r, light, 1);
            }
            const q = M.toQ8(lightAt(st, po, n, d, light));
            return .{ .cls = P.CLS_MAT + h.id, .q = @intCast(q), .fog = 0 };
        }

        /// Diffuse + Phong intensity 0..1 at a surface point (one shadow ray).
        fn lightAt(st: *Stats, po: V, n: V, d: V, light: V) T {
            const diff = n.dot(light);
            var lit = M.mul(AMB, M.k(0.78));
            if (diff <= 0) return lit;
            st.rays += 1;
            if (S.occluded(po, light)) return lit;
            lit = M.mul(AMB + M.mul(diff, M.ONE - AMB), M.k(0.78));
            const refl = n.scale(M.mul(diff, M.k(2.0))).sub(light);
            var sp = -refl.dot(d);
            if (sp <= 0) return lit;
            sp = M.mul(sp, sp);
            sp = M.mul(sp, sp);
            sp = M.mul(sp, sp);
            sp = M.mul(sp, sp); // ^16
            return lit + M.mul(sp, M.k(0.3));
        }
    };
}
