// The tracer of modes 1 and 2: one primary ray per sample, then at most one
// hard-shadow ray and (for the chrome sphere) one reflection ray, each shaded to
// a Shade (shade.zig) that colour.zig turns into RGB. Generic over the number
// back-end, so the fixed-point and the f32 modes are the same source. No float
// appears here in the fixed-point build: constants go through M.k at compile
// time, everything else through M's operators. Mode 3 (astro/) is the same
// maths as arrays, from the f64 constants below.
//
// sample(j) is the ray through a sub-pixel offset under one of the light disc's
// directions (samples.zig); sample 0 is the pixel's centre under the sun, the
// first picture's.
const Vec = @import("vec.zig").Vec;
const Sdf = @import("sdf.zig").Sdf;
const P = @import("shade.zig");
const samples = @import("samples.zig");

pub const IMG_W: u32 = 320;
pub const IMG_H: u32 = 176; // rows 176..199 are the HUD
pub const HORIZON_ROW: i32 = 62;
// The scene's constants as f64, for every back-end (M.k) and for mode 3's arrays.
pub const CAM_F = [3]f64{ 0.0, 1.7, -6.5 };
pub const PIXEL_F: f64 = 1.0 / 240.0; // image-plane units per pixel (focal length 1)
pub const AMB_F: f64 = 0.16;
pub const DIFFUSE_F: f64 = 0.78; // a material's light at full diffuse, the rest is highlight
pub const SPEC_F: f64 = 0.3;
pub const SKY_F: f64 = 2.2; // sky ramp position per unit of the ray's height
pub const FOG_F: f64 = 1.0 / 30.0; // fog per unit of floor distance
pub const SHADOW_Q: u16 = 80; // a shadowed floor tile's intensity, of 256

pub const Stats = struct { rays: u32 };

/// Toward the light, unnormalised: up, left and behind the camera.
pub const SUN_DIR = [3]f64{ -0.6, 0.55, -0.35 };

pub fn Tracer(comptime M: type) type {
    const T = M.T;
    const V = Vec(M);
    const S = Sdf(M);
    return struct {
        const CAM = V.of(M.k(CAM_F[0]), M.k(CAM_F[1]), M.k(CAM_F[2]));
        const PIXEL = M.k(PIXEL_F);
        const AMB = M.k(AMB_F);
        const Smp = samples.Samples(M, V);

        /// Sample j (samples.zig) of the pixel at (x, y); counts every ray.
        pub fn sample(st: *Stats, x: u32, y: u32, j: u32) P.Shade {
            const u = M.mul(M.fromInt(@as(i32, @intCast(x)) - 160) + Smp.JX[j], PIXEL);
            const v = M.mul(M.fromInt(HORIZON_ROW - @as(i32, @intCast(y))) - Smp.JY[j], PIXEL);
            return trace(st, CAM, V.of(u, v, M.ONE).unit(), Smp.LIGHTS[j], 0);
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
            return .{ .cls = P.CLS_SKY, .q = @intCast(M.toQ8(M.mul(d.y, M.k(SKY_F)))), .fog = 0 };
        }

        fn floor(st: *Stats, p: V, t: T, light: V) P.Shade {
            const tone: u8 = @intCast((M.toInt(p.x) + M.toInt(p.z)) & 1);
            st.rays += 1;
            const lit = !S.occluded(V.of(p.x, S.SELF, p.z), light);
            const fog = M.toQ8(M.mul(t, M.k(FOG_F)));
            return .{ .cls = P.CLS_FLOOR + tone, .q = if (lit) 256 else SHADOW_Q, .fog = @intCast(fog) };
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
            var lit = M.mul(AMB, M.k(DIFFUSE_F));
            if (diff <= 0) return lit;
            st.rays += 1;
            if (S.occluded(po, light)) return lit;
            lit = M.mul(AMB + M.mul(diff, M.ONE - AMB), M.k(DIFFUSE_F));
            const refl = n.scale(M.mul(diff, M.k(2.0))).sub(light);
            var sp = -refl.dot(d);
            if (sp <= 0) return lit;
            sp = M.mul(sp, sp);
            sp = M.mul(sp, sp);
            sp = M.mul(sp, sp);
            sp = M.mul(sp, sp); // ^16
            return lit + M.mul(sp, M.k(SPEC_F));
        }
    };
}
