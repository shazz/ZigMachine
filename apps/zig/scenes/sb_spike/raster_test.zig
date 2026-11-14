// SB SPIKE: raster.zig natively (build.sh NATIVE_TESTS). Two triangles sharing an
// edge must tile with no gap and no overlap, the spans must cover the triangle's
// pixel centres (a pixel a full pixel inside is drawn, one a full pixel outside is
// not), the letterbox rows and the view's width clip, and each span's u0 must be
// the texture plane at its first pixel centre.
const std = @import("std");
const raster = @import("raster.zig");

const Span = extern struct { x0: i16, x1: i16, y: i16, _pad: u16 = 0, u0: u32, v0: u32, du: u32, dv: u32 };
const W = 64;
const H = 48;
const Y0 = 3;
const Y1 = H - 3;

const Sink = struct {
    buf: [4096]Span = undefined,
    cur: [*]Span = undefined,
    end: [*]Span = undefined,
    pixels: u32 = 0,
    fn init(self: *Sink) void {
        self.cur = &self.buf;
        self.end = self.cur + self.buf.len;
    }
    fn spans(self: *const Sink) []const Span {
        return self.buf[0 .. (@intFromPtr(self.cur) - @intFromPtr(&self.buf)) / @sizeOf(Span)];
    }
    pub fn swap(_: *Sink) void {
        @panic("raster_test: span buffer full");
    }
};

fn draw(sink: *Sink, tris: []const [3]raster.P) void {
    sink.init();
    var e = raster.Emitter(Sink){ .sink = sink, .y_min = Y0, .y_max = Y1, .w = W };
    for (tris) |t| e.tri(t[0], t[1], t[2]);
}

fn f(v: anytype) f64 {
    return @floatFromInt(v);
}

/// Signed distance-ish of centre (x, y) from edge p -> q, in pixels (positive on the left).
fn side(p: raster.P, q: raster.P, x: f64, y: f64) f64 {
    const ex = f(q.x - p.x) / 16;
    const ey = f(q.y - p.y) / 16;
    return (ex * (y - f(p.y) / 16) - ey * (x - f(p.x) / 16)) / @sqrt(ex * ex + ey * ey);
}

test "a convex quad of two triangles: each centre inside once, none twice, clipped" {
    var prng = std.Random.DefaultPrng.init(0x5B);
    const r = prng.random();
    for (0..400) |_| {
        // four points on an ellipse in angle order: a convex quad, sometimes past the view
        var q: [4]raster.P = undefined;
        const cx = r.float(f64) * 90 - 13;
        const cy = r.float(f64) * 70 - 11;
        const rx = 3 + r.float(f64) * 60;
        const ry = 3 + r.float(f64) * 50;
        var ang = r.float(f64) * 6.28;
        for (&q) |*p| {
            ang += 0.3 + r.float(f64) * 1.2;
            p.* = .{ .x = @intFromFloat((cx + rx * @cos(ang)) * 16), .y = @intFromFloat((cy + ry * @sin(ang)) * 16), .u = 0, .v = 0 };
        }
        var sink = Sink{};
        draw(&sink, &.{ .{ q[0], q[1], q[2] }, .{ q[0], q[2], q[3] } });
        var grid = std.mem.zeroes([H][W]u8);
        for (sink.spans()) |s| {
            try std.testing.expect(s.y >= Y0 and s.y < Y1 and s.x0 >= 0 and s.x1 <= W and s.x0 < s.x1);
            for (@intCast(s.x0)..@intCast(s.x1)) |x| grid[@intCast(s.y)][x] += 1;
        }
        // the winding the ellipse walk gave: inside is where every side has its sign
        const sgn: f64 = if (side(q[0], q[1], f(q[2].x) / 16, f(q[2].y) / 16) > 0) 1 else -1;
        for (Y0..Y1) |y| for (0..W) |x| {
            const px = f(x) + 0.5;
            const py = f(y) + 0.5;
            var d: f64 = std.math.inf(f64);
            for (0..4) |i| d = @min(d, sgn * side(q[i], q[(i + 1) % 4], px, py));
            try std.testing.expect(grid[y][x] <= 1);
            if (d > 1.0) try std.testing.expectEqual(@as(u8, 1), grid[y][x]);
            if (d < -1.0) try std.testing.expectEqual(@as(u8, 0), grid[y][x]);
        };
    }
}

test "u0 is the texture plane at the span's first pixel centre" {
    var prng = std.Random.DefaultPrng.init(0x5C);
    const r = prng.random();
    for (0..300) |_| {
        var p: [3]raster.P = undefined;
        for (&p) |*q| q.* = .{
            .x = r.intRangeAtMost(i32, 0, W * 16),
            .y = r.intRangeAtMost(i32, 0, H * 16),
            .u = r.intRangeAtMost(u32, 0, 255) << 16,
            .v = r.intRangeAtMost(u32, 0, 255) << 16,
        };
        const area = f((p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[2].x - p[0].x) * (p[1].y - p[0].y));
        if (@abs(area) < 16 * 16 * 64) continue; // slivers: the plane is ill-conditioned
        var sink = Sink{};
        draw(&sink, &.{.{ p[0], p[1], p[2] }});
        for (sink.spans()) |s| {
            const x = f(s.x0) * 16 + 8 - f(p[0].x);
            const y = f(s.y) * 16 + 8 - f(p[0].y);
            const w1 = (x * f(p[2].y - p[0].y) - f(p[2].x - p[0].x) * y) / area;
            const w2 = (f(p[1].x - p[0].x) * y - x * f(p[1].y - p[0].y)) / area;
            const u = f(p[0].u) + w1 * (f(p[1].u) - f(p[0].u)) + w2 * (f(p[2].u) - f(p[0].u));
            const v = f(p[0].v) + w1 * (f(p[1].v) - f(p[0].v)) + w2 * (f(p[2].v) - f(p[0].v));
            try std.testing.expect(@abs(u - f(s.u0)) < 0.5 * 65536.0);
            try std.testing.expect(@abs(v - f(s.v0)) < 0.5 * 65536.0);
        }
    }
}
