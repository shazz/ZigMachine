// --------------------------------------------------------------------------
// SB SPIKE: a textured triangle as CHISEL AFFINE spans, with subpixel edges.
//
// Vertices are Q4 (xform.zig). A row y covers the triangle where its pixel centres
// (y + 0.5) fall; a span is the pixels whose centre x + 0.5 lies in [left, right):
// x0 = ceil(left - 0.5), x1 = ceil(right - 0.5). Each edge is stepped from its upper
// end with one slope (one divide an edge), so two triangles that share an edge meet
// with no gap and no overlap. u, v are planes over the screen (grad.zig: one divide a
// triangle); each span's u0, v0 is the plane at its first pixel centre, two wrapping
// multiply-adds, so x clipping is free (u0 is taken at the clipped x0). The obj
// demo's texmap.zig does the same with integer vertices and a divide a row per edge,
// too slow for 6,000 triangles. No 64-bit maths but for vertices far off screen.
// No ZigOS import: raster_test.zig checks the spans natively.
// --------------------------------------------------------------------------
const grad = @import("grad.zig");

pub const P = struct { x: i32, y: i32, u: u32, v: u32 };
const BIG: i32 = 1 << 13;
const SLOPE_MAX: i32 = 1 << 26; // 1,024 px a row: flatter edges are clamped (they are off screen)

pub fn Emitter(comptime Sink: type) type {
    return struct {
        sink: *Sink,
        y_min: i32,
        y_max: i32, // exclusive
        w: i32,

        const Self = @This();
        const Edge = struct { x: i32, dx: i32 };

        pub fn tri(self: *Self, a0: P, b0: P, c0: P) void {
            var a = a0;
            var b = b0;
            var c = c0;
            if (b.y < a.y) swap(&a, &b);
            if (c.y < b.y) swap(&b, &c);
            if (b.y < a.y) swap(&a, &b);
            const ya = @max(firstRow(a.y), self.y_min);
            const yc = @min(firstRow(c.y), self.y_max);
            if (ya >= yc) return;
            const ab = grad.V2{ b.x - a.x, b.y - a.y };
            const ac = grad.V2{ c.x - a.x, c.y - a.y };
            const area: i64 = if (@abs(ab[0]) < BIG and @abs(ac[0]) < BIG and @abs(ab[1]) < BIG and @abs(ac[1]) < BIG)
                ab[0] * ac[1] - ac[0] * ab[1]
            else
                @as(i64, ab[0]) * ac[1] - @as(i64, ac[0]) * ab[1]; // Q8
            if (area == 0) return;
            const g = grad.plane(ab, ac, .{ delta(b.u, a.u), delta(c.u, a.u) }, .{ delta(b.v, a.v), delta(c.v, a.v) }, area);
            const uo = origin(a.u, g.dudx, g.dudy, a.x, a.y);
            const vo = origin(a.v, g.dvdx, g.dvdy, a.x, a.y);
            var long = edge(a.x, a.y, c.x, c.y, ya);
            const yb = @min(@max(firstRow(b.y), ya), yc);
            var short = if (yb > ya) edge(a.x, a.y, b.x, b.y, ya) else Edge{ .x = 0, .dx = 0 }; // b's row first: b -> c at once
            const right_long = area < 0; // b left of the long edge (screen y down)
            var o = Out{ .cur = self.sink.cur, .end = self.sink.end };
            var y = ya;
            var ru = uo +% g.dudy *% @as(u32, @bitCast(y));
            var rv = vo +% g.dvdy *% @as(u32, @bitCast(y));
            while (y < yc) : (y += 1) {
                if (y == yb) short = edge(b.x, b.y, c.x, c.y, y);
                const l = if (right_long) short.x else long.x;
                const r = if (right_long) long.x else short.x;
                self.span(&o, y, l, r, ru, rv, g);
                long.x +%= long.dx;
                short.x +%= short.dx;
                ru +%= g.dudy;
                rv +%= g.dvdy;
            }
            self.sink.cur = o.cur;
            self.sink.pixels +%= o.px;
        }

        /// The sink's cursor, held in registers for one triangle.
        const Out = struct { cur: [*]Span, end: [*]Span, px: u32 = 0 };
        const Span = @typeInfo(@TypeOf(@as(Sink, undefined).cur)).pointer.child;
        comptime {
            if (@sizeOf(Span) != 24 or @alignOf(Span) < 4) @compileError("raster: a span is six aligned words");
        }

        inline fn span(self: *Self, o: *Out, y: i32, l: i32, r: i32, ru: u32, rv: u32, g: grad.Grad) void {
            const x0: i32 = @max((l +% 0x7FFF) >> 16, 0);
            const x1: i32 = @min((r +% 0x7FFF) >> 16, self.w);
            if (x1 <= x0) return;
            if (o.cur == o.end) {
                self.sink.cur = o.cur;
                self.sink.swap();
                o.cur = self.sink.cur;
                o.end = self.sink.end;
            }
            // the 24-byte record as six word stores (x0 | x1 << 16, y | 0 << 16, u0, v0, du, dv)
            const s: *[6]u32 = @ptrCast(&o.cur[0]);
            o.cur += 1;
            o.px +%= @intCast(x1 - x0);
            const xu: u32 = @bitCast(x0);
            s.* = .{ @as(u32, @bitCast(x0)) | @as(u32, @bitCast(x1)) << 16, @bitCast(y), ru +% g.dudx *% xu, rv +% g.dvdx *% xu, g.dudx, g.dvdx };
        }

        /// The plane at the screen's pixel (0, 0) centre, for vertex value t at (x, y) Q4:
        /// t - dx * x - dy * y + (dx + dy) / 2, mod 2^32 (u, v wrap): the whole-pixel part
        /// as wrapping u32 products, the 1/16 px remainder (< 16) in i32.
        inline fn origin(t: u32, dx: u32, dy: u32, x: i32, y: i32) u32 {
            const whole = dx *% @as(u32, @bitCast(x >> 4)) +% dy *% @as(u32, @bitCast(y >> 4));
            const frac: i32 = (@as(i32, @bitCast(dx)) >> 4) * (x & 15) + (@as(i32, @bitCast(dy)) >> 4) * (y & 15);
            const half: i32 = (@as(i32, @bitCast(dx)) >> 1) + (@as(i32, @bitCast(dy)) >> 1);
            return t -% whole -% @as(u32, @bitCast(frac)) +% @as(u32, @bitCast(half));
        }

        fn swap(p: *P, q: *P) void {
            const t = p.*;
            p.* = q.*;
            q.* = t;
        }

        /// The first row whose centre is at or below y (Q4).
        fn firstRow(y: i32) i32 {
            return (y - 8 + 15) >> 4;
        }

        /// Edge p -> q (p the upper end) at row y: x 16.16 and its step a row. Inline and
        /// on scalars: a P passed by value went through the stack (~40 cycles a call).
        inline fn edge(px: i32, py: i32, qx: i32, qy: i32, y: i32) Edge {
            const h = qy - py;
            if (h <= 0) return .{ .x = px << 12, .dx = 0 };
            var slope: i32 = @divTrunc((qx - px) << 12, h) << 4; // px a row, 16.16
            slope = @max(-SLOPE_MAX, @min(SLOPE_MAX, slope));
            const first = firstRow(py);
            const frac = (first << 4) + 8 - py; // 0..15: the vertex to its first row centre
            var x = (px << 12) + (slope >> 4) * frac;
            if (y > first) x +%= @truncate(@as(i64, slope) * (y - first)); // rows clipped away (rare)
            return .{ .x = x, .dx = slope };
        }

        fn delta(p: u32, q: u32) i32 {
            return @as(i32, @bitCast(p -% q)) >> 8; // 8.8 texels
        }
    };
}
