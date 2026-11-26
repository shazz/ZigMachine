// --------------------------------------------------------------------------
// RACER: a convex polygon as flat spans, with sub-pixel edges. ONE emitter; the CPU fill and the
// CHISEL AFFINE fill are both a Sink with `span(y, x0, x1, colour)`, so the two paths cannot
// disagree about a pixel (the harness checks them byte for byte).
//
// Vertices are Q4 (1/16 px). A row y covers the polygon where its pixel centre (y + 0.5) falls;
// a span is the pixels whose centre lies in [left, right): x0 = ceil(left - 0.5), x1 = ceil(right
// - 0.5). Each edge is walked from its UPPER end with one slope (one divide an edge) whatever
// polygon it belongs to, so two polygons sharing an edge meet with no gap and no double row
// (poly_test.zig, the method of stniccc/polyfill_test.zig). The edge maths is sb_spike/raster.zig's.
// No ZigOS import.
// --------------------------------------------------------------------------
pub const MAXV = 9;
const SLOPE_MAX: i32 = 1 << 26;

/// Set by the harness' --break edge: the right edge is rounded the other way (a gap / double row).
pub var break_edge: bool = false;

const Edge = struct { x: i32, dx: i32, end: i32 }; // x 16.16 at the row's centre, step a row, first row NOT covered

/// The first row whose centre is at or below y (Q4).
inline fn firstRow(y: i32) i32 {
    return (y - 8 + 15) >> 4;
}

inline fn edge(px: i32, py: i32, qx: i32, qy: i32, y: i32) Edge {
    const h = qy - py;
    const end = firstRow(qy);
    if (h <= 0) return .{ .x = px << 12, .dx = 0, .end = end };
    var slope: i32 = @divTrunc((qx - px) << 12, h) << 4;
    slope = @max(-SLOPE_MAX, @min(SLOPE_MAX, slope));
    const first = firstRow(py);
    const frac = (first << 4) + 8 - py;
    var x = (px << 12) + (slope >> 4) * frac;
    if (y > first) x +%= @truncate(@as(i64, slope) * (y - first));
    return .{ .x = x, .dx = slope, .end = end };
}

pub fn Emitter(comptime Sink: type) type {
    return struct {
        sink: *Sink,
        y_min: i32,
        y_max: i32, // exclusive
        w: i32,

        const Self = @This();

        pub fn poly(self: *Self, xs: []const i32, ys: []const i32, c: u8) void {
            self.walk(xs, ys, c, false);
        }

        /// A car's shadow: the same edges and pixels as poly(), each span darkened in place (Sink.shade) instead of filled.
        pub fn shadow(self: *Self, xs: []const i32, ys: []const i32) void {
            self.walk(xs, ys, 0, true);
        }

        inline fn walk(self: *Self, xs: []const i32, ys: []const i32, c: u8, comptime shade: bool) void {
            const n = xs.len;
            var top: usize = 0;
            var bot: usize = 0;
            for (ys, 0..) |y, i| {
                if (y < ys[top]) top = i;
                if (y > ys[bot]) bot = i;
            }
            const ya = @max(firstRow(ys[top]), self.y_min);
            const yc = @min(firstRow(ys[bot]), self.y_max);
            var ia = top;
            var ib = top;
            var a = Edge{ .x = 0, .dx = 0, .end = ya }; // forces an advance at the first row
            var b = a;
            var y = ya;
            while (y < yc) : (y += 1) {
                while (a.end <= y) {
                    const ja = (ia + 1) % n;
                    a = edge(xs[ia], ys[ia], xs[ja], ys[ja], y);
                    ia = ja;
                }
                while (b.end <= y) {
                    const jb = (ib + n - 1) % n;
                    b = edge(xs[ib], ys[ib], xs[jb], ys[jb], y);
                    ib = jb;
                }
                const l = @min(a.x, b.x);
                const r = @max(a.x, b.x);
                self.row(y, l, r, c, shade);
                a.x +%= a.dx;
                b.x +%= b.dx;
            }
        }

        inline fn row(self: *Self, y: i32, l: i32, r: i32, c: u8, comptime shade: bool) void {
            const bias: i32 = if (break_edge) 0x8000 else 0x7FFF;
            const x0 = @max((l +% 0x7FFF) >> 16, 0);
            const x1 = @min((r +% bias) >> 16, self.w);
            if (x1 <= x0) return;
            if (shade) self.sink.shade(y, x0, x1) else self.sink.span(y, x0, x1, c);
        }
    };
}
