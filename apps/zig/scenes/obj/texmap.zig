// --------------------------------------------------------------------------
// OBJ demo: a triangle cut into AFFINE spans for CHISEL v2 (COMMAND 6): one
// span a row, pixels [x0, x1) reading texel (u >> 16, v >> 16) with u, v
// stepping by du, dv a pixel. The whole frame's faces go into ONE list, far
// first, so CHISEL draws them in the painter's order in a single op.
//
// Affine mapping: u and v are planes over the screen triangle, so du/dx,
// dv/dx (the span steps) and du/dy, dv/dy are constants a face. They come
// from the plane equation over twice the area D, through one reciprocal of D
// a face and four `mul16`s (ZM-X's mulsh on the board: the 64-bit product's
// middle word in one instruction). Each row's u0, v0 is then two wrapping
// multiply-adds: u wraps modulo 2^32, which keeps the texture's own wrap.
//
// Rows: an edge is always stepped from its upper end (the same rounding in
// both faces that share it), x rounds up, a span is [ceil(left), ceil(right)),
// so neighbours meet with no gap and no overlap. Integers only.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------

/// A vertex's texture coordinates, 16.16 texels (wrapping).
pub const UV = [2]u32;
pub const P = [2]i16;

pub fn Spans(comptime Span: type, comptime mul16: fn (i32, i32) i32) type {
    return struct {
        out: []Span,
        n: usize = 0,
        w: i32,
        h: i32,

        const Self = @This();

        /// Append the spans of triangle p (uv at its corners); silently stops when full.
        pub fn tri(self: *Self, p: [3]P, uv: [3]UV) void {
            var v = order(p, uv);
            const d = area(v.p);
            if (d == 0) return;
            const g = gradients(v.p, v.uv, d);
            const ya: i32 = @max(@as(i32, v.p[0][1]), 0);
            const yb: i32 = @min(@as(i32, v.p[2][1]), self.h);
            var y: i32 = ya;
            while (y < yb) : (y += 1) {
                const l = edgeX(v.p[0], v.p[2], y);
                const s = if (y < v.p[1][1]) edgeX(v.p[0], v.p[1], y) else edgeX(v.p[1], v.p[2], y);
                self.row(y, @min(l, s), @max(l, s), &v, g);
            }
        }

        fn row(self: *Self, y: i32, xl16: i32, xr16: i32, v: *const Tri, g: Grad) void {
            const x0: i32 = @max((xl16 + 0xFFFF) >> 16, 0);
            const x1: i32 = @min((xr16 + 0xFFFF) >> 16, self.w);
            if (x1 <= x0 or self.n >= self.out.len) return;
            const dx: u32 = @bitCast(x0 - v.p[0][0]);
            const dy: u32 = @bitCast(y - v.p[0][1]);
            self.out[self.n] = .{
                .x0 = @intCast(x0),
                .x1 = @intCast(x1),
                .y = @intCast(y),
                .u0 = v.uv[0][0] +% g.dudx *% dx +% g.dudy *% dy,
                .v0 = v.uv[0][1] +% g.dvdx *% dx +% g.dvdy *% dy,
                .du = g.dudx,
                .dv = g.dvdx,
            };
            self.n += 1;
        }

        const Tri = struct { p: [3]P, uv: [3]UV };
        const Grad = struct { dudx: u32, dudy: u32, dvdx: u32, dvdy: u32 };

        /// The corners by rising y (screen y grows down).
        fn order(p: [3]P, uv: [3]UV) Tri {
            var t = Tri{ .p = p, .uv = uv };
            inline for (.{ .{ 0, 1 }, .{ 1, 2 }, .{ 0, 1 } }) |ij| {
                if (t.p[ij[1]][1] < t.p[ij[0]][1]) {
                    const tp = t.p[ij[0]];
                    t.p[ij[0]] = t.p[ij[1]];
                    t.p[ij[1]] = tp;
                    const tu = t.uv[ij[0]];
                    t.uv[ij[0]] = t.uv[ij[1]];
                    t.uv[ij[1]] = tu;
                }
            }
            return t;
        }

        fn area(p: [3]P) i32 {
            const ax: i32 = @as(i32, p[1][0]) - p[0][0];
            const ay: i32 = @as(i32, p[1][1]) - p[0][1];
            const bx: i32 = @as(i32, p[2][0]) - p[0][0];
            const by: i32 = @as(i32, p[2][1]) - p[0][1];
            return ax * by - bx * ay;
        }

        /// d(c)/dx and d(c)/dy of one coordinate in 16.16, given twice the area d.
        /// The deltas go in at 8.8 (|delta| < 2^23 >> 8, times a span < 2^9: no overflow),
        /// inv = 2^31 / |d|, and mul16(num, inv) >> 7 = num * 2^8 / d in 16.16.
        fn grad(p: [3]P, c0: u32, c1: u32, c2: u32, inv: i32, neg: bool) [2]u32 {
            const d1: i32 = @as(i32, @bitCast(c1 -% c0)) >> 8;
            const d2: i32 = @as(i32, @bitCast(c2 -% c0)) >> 8;
            const ax: i32 = @as(i32, p[1][0]) - p[0][0];
            const ay: i32 = @as(i32, p[1][1]) - p[0][1];
            const bx: i32 = @as(i32, p[2][0]) - p[0][0];
            const by: i32 = @as(i32, p[2][1]) - p[0][1];
            var gx = mul16(d1 * by - d2 * ay, inv) >> 7;
            var gy = mul16(d2 * ax - d1 * bx, inv) >> 7;
            if (neg) {
                gx = -gx;
                gy = -gy;
            }
            return .{ @bitCast(gx), @bitCast(gy) };
        }

        fn gradients(p: [3]P, uv: [3]UV, d: i32) Grad {
            const ad: u32 = @abs(d);
            const inv: i32 = @intCast(@as(u32, 1 << 31) / @max(ad, 2));
            const gu = grad(p, uv[0][0], uv[1][0], uv[2][0], inv, d < 0);
            const gv = grad(p, uv[0][1], uv[1][1], uv[2][1], inv, d < 0);
            return .{ .dudx = gu[0], .dudy = gu[1], .dvdx = gv[0], .dvdy = gv[1] };
        }

        /// The edge a -> b (a the upper end) at row y, 16.16; b's x on a flat edge.
        fn edgeX(a: P, b: P, y: i32) i32 {
            const h: i32 = @as(i32, b[1]) - a[1];
            if (h <= 0) return @as(i32, b[0]) << 16;
            const slope = @divTrunc((@as(i32, b[0]) - a[0]) << 16, h);
            return (@as(i32, a[0]) << 16) + slope * (y - a[1]);
        }
    };
}

/// TEXTURE's box map: a face takes its uv from the two object axes across its
/// dominant normal axis (x, y or z by the largest |n|), so no face sees its tiles
/// stretched edge-on. Q14 corners (|v| <= 2), the texture once across the unit cube.
pub fn boxUV(p: [3][4]i16) [3]UV {
    var n: [3]i32 = undefined;
    const e1 = [3]i32{ @as(i32, p[1][0]) - p[0][0], @as(i32, p[1][1]) - p[0][1], @as(i32, p[1][2]) - p[0][2] };
    const e2 = [3]i32{ @as(i32, p[2][0]) - p[0][0], @as(i32, p[2][1]) - p[0][1], @as(i32, p[2][2]) - p[0][2] };
    for (0..3) |k| n[k] = @intCast(@abs((e1[(k + 1) % 3] >> 4) * (e2[(k + 2) % 3] >> 4) - (e1[(k + 2) % 3] >> 4) * (e2[(k + 1) % 3] >> 4)));
    const axis: usize = if (n[0] >= n[1] and n[0] >= n[2]) 0 else if (n[1] >= n[2]) 1 else 2;
    const iu = (axis + 1) % 3;
    const iv = (axis + 2) % 3;
    var uv: [3]UV = undefined;
    for (0..3) |i| uv[i] = .{ @bitCast((@as(i32, p[i][iu]) + 16384) << 8), @bitCast((@as(i32, p[i][iv]) + 16384) << 8) };
    return uv;
}
