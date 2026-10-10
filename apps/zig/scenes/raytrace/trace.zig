// The tracer: one primary ray per pixel, then at most one hard-shadow ray and
// (for the chrome sphere) one reflection ray, each shaded straight to a palette
// index. Generic over the number back-end, so fixed-point and f32 carts are the
// same source. No float appears here in the fixed-point build: constants go
// through M.k at compile time, everything else through M's operators.
const Vec = @import("vec.zig").Vec;
const Sdf = @import("sdf.zig").Sdf;
const P = @import("palette.zig");

pub const IMG_W: u32 = 320;
pub const IMG_H: u32 = 176; // rows 176..199 are the HUD
const HORIZON_ROW: i32 = 62;

pub const Stats = struct { rays: u32 };

pub fn Tracer(comptime M: type) type {
    const T = M.T;
    const V = Vec(M);
    const S = Sdf(M);
    return struct {
        const CAM = V.of(M.k(0.0), M.k(1.7), M.k(-6.5));
        const PIXEL = M.k(1.0 / 240.0); // image-plane units per pixel (focal length 1)
        const AMB = M.k(0.16);
        // Unit vector TOWARD the light: up, left and behind the camera.
        const LIGHT = blk: {
            const x = -0.6;
            const y = 0.55;
            const z = -0.35;
            const n = @sqrt(x * x + y * y + z * z);
            break :blk V.of(M.k(x / n), M.k(y / n), M.k(z / n));
        };

        /// Palette index for the pixel at (x, y); counts every ray it casts.
        pub fn pixel(st: *Stats, x: u32, y: u32) u8 {
            const u = M.mul(M.fromInt(@as(i32, @intCast(x)) - 160), PIXEL);
            const v = M.mul(M.fromInt(HORIZON_ROW - @as(i32, @intCast(y))), PIXEL);
            return trace(st, CAM, V.of(u, v, M.ONE).unit(), P.bayer(x, y), 0);
        }

        fn trace(st: *Stats, o: V, d: V, bay: u32, depth: u8) u8 {
            st.rays += 1;
            const tf = S.floorT(o, d);
            const tmax = if (tf) |f| @min(f, S.TMAX) else S.TMAX;
            const h = S.march(o, d, tmax);
            if (h.id != S.NONE) return sphere(st, o, d, h, bay, depth);
            if (tf) |f| if (f < S.TMAX) return floor(st, o.at(d, f), f, bay);
            return sky(d, bay);
        }

        fn sky(d: V, bay: u32) u8 {
            const q = M.toQ8(M.mul(d.y, M.k(2.2)));
            return P.SKY_BASE + P.quant(q, P.SKY_LV, bay);
        }

        fn floor(st: *Stats, p: V, t: T, bay: u32) u8 {
            const tone: u32 = @intCast((M.toInt(p.x) + M.toInt(p.z)) & 1);
            st.rays += 1;
            const lit = !S.occluded(V.of(p.x, S.SELF, p.z), LIGHT);
            const shade = P.quant(if (lit) 256 else 80, P.SHADE_LV, bay);
            const fog = P.quant(M.toQ8(M.mul(t, M.k(1.0 / 30.0))), P.FOG_LV, 255 - bay);
            return P.FLOOR_BASE + @as(u8, @intCast((tone * P.FOG_LV + fog) * P.SHADE_LV + shade));
        }

        fn sphere(st: *Stats, o: V, d: V, h: S.Hit, bay: u32, depth: u8) u8 {
            const s = S.spheres[h.id];
            const p = o.at(d, h.t);
            const n = p.sub(s.c).scale(s.inv_r);
            const po = p.add(n.scale(S.SELF));
            if (h.id == 0 and depth == 0) {
                const r = d.sub(n.scale(M.mul(d.dot(n), M.k(2.0))));
                return trace(st, po, r, bay, 1);
            }
            const q = M.toQ8(lightAt(st, po, n, d));
            return P.MAT_BASE + h.id * P.MAT_LV + P.quant(q, P.MAT_LV, bay);
        }

        /// Diffuse + Phong intensity 0..1 at a surface point (one shadow ray).
        fn lightAt(st: *Stats, po: V, n: V, d: V) T {
            const diff = n.dot(LIGHT);
            var lit = M.mul(AMB, M.k(0.78));
            if (diff <= 0) return lit;
            st.rays += 1;
            if (S.occluded(po, LIGHT)) return lit;
            lit = M.mul(AMB + M.mul(diff, M.ONE - AMB), M.k(0.78));
            const refl = n.scale(M.mul(diff, M.k(2.0))).sub(LIGHT);
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
