// RACER natively: the edge rule (the method of stniccc/polyfill_test.zig). Polygons that share an
// edge must tile with no gap and no double row, the pixel set of a split polygon is the whole
// one's, the viewport clips, and the harness' --break edge switch must break exactly this.
const std = @import("std");
const poly = @import("poly.zig");

const W = 64;
const H = 48;
const Y0 = 3;
const Y1 = 45;

const Grid = struct {
    hits: [W * H]u8 = [_]u8{0} ** (W * H),
    spans: u32 = 0,
    pub fn span(self: *Grid, y: i32, x0: i32, x1: i32, _: u8) void {
        self.spans += 1;
        var x = x0;
        while (x < x1) : (x += 1) self.hits[@intCast(y * W + x)] += 1;
    }
    fn at(self: *const Grid, x: usize, y: usize) u8 {
        return self.hits[y * W + x];
    }
};

fn fill(g: *Grid, pts: []const [2]i32) void {
    var xs: [poly.MAXV]i32 = undefined;
    var ys: [poly.MAXV]i32 = undefined;
    for (pts, 0..) |p, i| {
        xs[i] = p[0];
        ys[i] = p[1];
    }
    var e = poly.Emitter(Grid){ .sink = g, .y_min = Y0, .y_max = Y1, .w = W };
    e.poly(xs[0..pts.len], ys[0..pts.len], 1);
}

/// A random convex quad (points on an ellipse in angle order), Q4.
fn quad(r: std.Random) [4][2]i32 {
    const cx = r.float(f64) * 90 - 13;
    const cy = r.float(f64) * 70 - 11;
    const rx = 3 + r.float(f64) * 60;
    const ry = 3 + r.float(f64) * 50;
    var out: [4][2]i32 = undefined;
    var a = r.float(f64) * 6.28;
    for (&out) |*p| {
        p.* = .{ @intFromFloat((cx + rx * @cos(a)) * 16), @intFromFloat((cy + ry * @sin(a)) * 16) };
        a += 1.2 + r.float(f64) * 0.55; // < 2 pi in four steps
    }
    return out;
}

test "a quad split on its diagonal: no pixel twice, the same pixels as the whole quad (400 random)" {
    var prng = std.Random.DefaultPrng.init(0xACE);
    for (0..400) |_| {
        const q = quad(prng.random());
        var whole = Grid{};
        var parts = Grid{};
        fill(&whole, &q);
        fill(&parts, &.{ q[0], q[1], q[2] });
        fill(&parts, &.{ q[0], q[2], q[3] });
        for (0..W * H) |i| {
            try std.testing.expect(parts.hits[i] <= 1); // no double row
            try std.testing.expectEqual(whole.hits[i], parts.hits[i]); // no gap either
        }
    }
}

test "two neighbours sharing a vertical edge on a pixel centre: one owner for the shared column" {
    var g = Grid{};
    fill(&g, &.{ .{ 16, 48 }, .{ 40, 48 }, .{ 40, 200 }, .{ 16, 200 } }); // x 1.0 .. 2.5
    fill(&g, &.{ .{ 40, 48 }, .{ 72, 48 }, .{ 72, 200 }, .{ 40, 200 } }); // x 2.5 .. 4.5
    for (Y0..12) |y| {
        for (1..4) |x| try std.testing.expectEqual(@as(u8, 1), g.at(x, y)); // columns 1, 2 | 3 (x = 2.5 is column 3's near edge)
        try std.testing.expectEqual(@as(u8, 0), g.at(0, y));
        try std.testing.expectEqual(@as(u8, 0), g.at(4, y));
    }
}

test "--break edge turns that shared column into a double row" {
    poly.break_edge = true;
    defer poly.break_edge = false;
    var g = Grid{};
    fill(&g, &.{ .{ 16, 48 }, .{ 40, 48 }, .{ 40, 200 }, .{ 16, 200 } });
    fill(&g, &.{ .{ 40, 48 }, .{ 72, 48 }, .{ 72, 200 }, .{ 40, 200 } });
    try std.testing.expectEqual(@as(u8, 2), g.at(2, 5));
}

test "the viewport clips rows and the width; a polygon wholly outside draws nothing" {
    var g = Grid{};
    fill(&g, &.{ .{ -400, -400 }, .{ 2000, -400 }, .{ 2000, 1000 }, .{ -400, 1000 } });
    for (0..H) |y| for (0..W) |x| {
        const want: u8 = if (y >= Y0 and y < Y1) 1 else 0;
        try std.testing.expectEqual(want, g.at(x, y));
    };
    var none = Grid{};
    fill(&none, &.{ .{ 2000, 100 }, .{ 2400, 100 }, .{ 2400, 300 } });
    fill(&none, &.{ .{ 100, -900 }, .{ 300, -900 }, .{ 300, -500 } });
    try std.testing.expectEqual(@as(u32, 0), none.spans);
}

test "degenerate polygons (a line, a point, flat) draw nothing and do not hang" {
    var g = Grid{};
    fill(&g, &.{ .{ 100, 100 }, .{ 100, 100 }, .{ 100, 100 } });
    fill(&g, &.{ .{ 100, 100 }, .{ 300, 100 }, .{ 500, 100 } });
    fill(&g, &.{ .{ 100, 100 }, .{ 100, 300 }, .{ 100, 500 } });
    try std.testing.expectEqual(@as(u32, 0), g.spans);
}

test "a nine-vertex convex polygon is filled whole (the widest a clipped quad can be)" {
    var g = Grid{};
    var pts: [9][2]i32 = undefined;
    for (&pts, 0..) |*p, i| {
        const a = @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / 9.0;
        p.* = .{ 512 + @as(i32, @intFromFloat(300 * @cos(a))), 384 + @as(i32, @intFromFloat(300 * @sin(a))) };
    }
    fill(&g, &pts);
    try std.testing.expect(g.at(32, 24) == 1 and g.at(2, 24) == 0 and g.at(32, 3) == 0);
}
