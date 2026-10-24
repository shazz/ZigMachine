// Native tests of the OBJ demo's integer 3D (zig test apps/zig/scene_tests.zig).
const std = @import("std");
const fx = @import("fixed3d.zig");
const fmesh = @import("fmesh.zig");
const sphere = @import("sphere.zig");
const raster = @import("raster.zig");
const xform = @import("xform.zig");
const T = std.testing;

test "the sine table: quadrants exact, angles wrap" {
    try T.expectEqual(@as(i32, 0), fx.sin16(0));
    try T.expectEqual(@as(i32, 65536), fx.sin16(1 << 30));
    try T.expectEqual(@as(i32, 65536), fx.cos16(0));
    try T.expectEqual(@as(i32, -65536), fx.sin16(3 << 30));
    const s = fx.sin16(fx.angle(0.5));
    try T.expect(@abs(s - 31420) <= 2); // sin(0.5) * 65536 = 31419.6
}

var mesh_buf: fmesh.Mesh = .{};
var frame_buf: xform.Frame = .{};

test "every sphere level: V and F as the formulas say, closed (Euler), outward" {
    for (sphere.LEVELS) |l| {
        const m = &mesh_buf;
        sphere.build(m, l);
        try T.expectEqual(sphere.verts(l), m.nverts);
        try T.expectEqual(sphere.faces(l), m.nfaces);
        try T.expectEqual(@as(u32, m.nverts) + m.nfaces - 2, m.nedges); // V - E + F = 2
        for (m.edges[0..m.nedges]) |e| try T.expect(e.f1 != fmesh.NO_FACE);
        for (m.inward[0..m.nfaces]) |b| try T.expect(!b);
        for (m.faces[0..m.nfaces], 0..) |f, i| { // each normal points away from the centre
            var c: [3]i32 = .{ 0, 0, 0 };
            for (0..3) |k| c[k] = @as(i32, m.verts[f.a][k]) + m.verts[f.b][k] + m.verts[f.c][k];
            try T.expect(fx.dot(m.fnorm[i], c) > 0);
        }
    }
}

test "the OBJ models: one winding per file, normals turned outward" {
    for ([_][]const u8{ @embedFile("../../assets/obj/icosahedron.obj"), @embedFile("../../assets/obj/gem.obj") }) |text| {
        const m = &mesh_buf;
        parseObj(m, text);
        m.finish();
        try T.expect(m.nfaces > 0);
        var inward: u32 = 0;
        for (m.inward[0..m.nfaces]) |b| inward += @intFromBool(b);
        try T.expect(inward == 0 or inward == m.nfaces); // one winding per file
        for (m.faces[0..m.nfaces], 0..) |f, i| {
            var c: [3]i32 = .{ 0, 0, 0 };
            for (0..3) |k| c[k] = @as(i32, m.verts[f.a][k]) + m.verts[f.b][k] + m.verts[f.c][k];
            try T.expect(fx.dot(m.fnorm[i], c) > 0);
        }
    }
}

/// Just enough of an OBJ reader for the test (the cart uses zigos' loader):
/// `v` lines (already within radius ~1.9: scaled by half) and triangle `f` lines.
fn parseObj(m: *fmesh.Mesh, text: []const u8) void {
    m.nverts = 0;
    m.nfaces = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |ln| {
        var t = std.mem.tokenizeAny(u8, ln, " \t\r");
        const kind = t.next() orelse continue;
        if (std.mem.eql(u8, kind, "v")) {
            for (0..3) |k| m.verts[m.nverts][k] = fmesh.q14(0.5 * (std.fmt.parseFloat(f32, t.next().?) catch 0));
            m.nverts += 1;
        } else if (std.mem.eql(u8, kind, "f")) {
            var idx: [3]u16 = undefined;
            for (&idx) |*v| v.* = (std.fmt.parseInt(u16, t.next().?, 10) catch 1) - 1;
            m.faces[m.nfaces] = .{ .a = idx[0], .b = idx[1], .c = idx[2] };
            m.nfaces += 1;
        }
    }
}

test "facing faces are the ones whose normal looks at the eye" {
    const m = &mesh_buf;
    sphere.build(m, sphere.LEVELS[4]);
    const fr = &frame_buf;
    fr.transform(m, fx.rotation(fx.angle(0.3), fx.angle(1.1), fx.angle(0.2)), false);
    const mat = fx.rotation(fx.angle(0.3), fx.angle(1.1), fx.angle(0.2));
    var seen: u32 = 0;
    for (0..m.nfaces) |i| {
        const f = m.faces[i];
        const n = fx.apply(mat, m.fnorm[i]);
        var look: i64 = 0; // n . (centre - eye), the eye at z = -DIST
        for (0..3) |k| {
            const c = @divTrunc(fx.apply(mat, m.verts[f.a])[k] + fx.apply(mat, m.verts[f.b])[k] + fx.apply(mat, m.verts[f.c])[k], 3);
            look += @as(i64, n[k]) * (c + if (k == 2) fx.DIST else 0);
        }
        if (@abs(look) < 4000 * 16384) continue; // grazing: rounding decides
        try T.expectEqual(look < 0, fr.facing(m, i));
        if (fr.facing(m, i)) seen += 1;
    }
    try T.expect(seen > m.nfaces / 4);
}

test "cullSort: far first, stable on equal depths" {
    const m = &mesh_buf;
    sphere.build(m, sphere.LEVELS[6]);
    const fr = &frame_buf;
    fr.transform(m, fx.rotation(fx.angle(0.7), fx.angle(0.4), 0), false);
    fr.cullSort(m, false);
    try T.expectEqual(m.nfaces, fr.nvis);
    var last: i32 = std.math.minInt(i32);
    var last_f: u16 = 0;
    for (fr.order[0..fr.nvis], 0..) |fi, k| {
        const f = m.faces[fi];
        const z = (60000 - (fr.z[f.a] + fr.z[f.b] + fr.z[f.c])) >> 1; // the depth key
        try T.expect(z >= last);
        if (k > 0 and z == last) try T.expect(fi > last_f);
        last = z;
        last_f = fi;
    }
}

// The machine's own triangle (machine/blitter.zig doTriangle + crossSpan).
fn chiselTri(px: []u8, xs: [3]i32, ys: [3]i32, color: u8) void {
    var y = @max(@min(ys[0], @min(ys[1], ys[2])), 0);
    const ymax = @min(@max(ys[0], @max(ys[1], ys[2])), 199);
    while (y <= ymax) : (y += 1) {
        var xl: i32 = std.math.maxInt(i32);
        var xr: i32 = std.math.minInt(i32);
        for (0..3) |e| {
            var ay = ys[e];
            var ax = xs[e];
            var by = ys[(e + 1) % 3];
            var bx = xs[(e + 1) % 3];
            if (ay == by) continue;
            if (ay > by) {
                std.mem.swap(i32, &ay, &by);
                std.mem.swap(i32, &ax, &bx);
            }
            if (y < ay or y >= by) continue;
            const x = ax + @divFloor((bx - ax) * (y - ay), (by - ay));
            xl = @min(xl, x);
            xr = @max(xr, x);
        }
        if (xr < xl) continue;
        var x = @max(xl, 0);
        while (x <= @min(xr, 319)) : (x += 1) px[@intCast(y * 320 + x)] = color;
    }
}

var pa: [320 * 200]u8 = undefined;
var pb: [320 * 200]u8 = undefined;

test "the CPU triangle covers exactly CHISEL's pixels (clipped ones too)" {
    var rng = std.Random.DefaultPrng.init(1234);
    const r = rng.random();
    const t = raster.Target{ .px = &pb, .stride = 320, .w = 320, .h = 200 };
    for (0..3000) |i| {
        var v: [3]raster.P = undefined;
        const span: i16 = if (i % 3 == 0) 400 else 40;
        for (&v) |*p| p.* = .{ r.intRangeAtMost(i16, -40, span), r.intRangeAtMost(i16, -30, @divTrunc(span, 2)) };
        @memset(&pa, 0);
        @memset(&pb, 0);
        chiselTri(&pa, .{ v[0][0], v[1][0], v[2][0] }, .{ v[0][1], v[1][1], v[2][1] }, 7);
        raster.flat(t, v, 7);
        try T.expectEqualSlices(u8, &pa, &pb);
        @memset(&pb, 0);
        raster.gouraud(t, v, .{ 3 << 12, 3 << 12, 3 << 12 }, 4, 31); // a flat level: the same pixels
        try T.expectEqualSlices(u8, &pa, &pb);
    }
}

test "Gouraud spans the levels between its vertices, clamped" {
    @memset(&pb, 0);
    const t = raster.Target{ .px = &pb, .stride = 320, .w = 320, .h = 200 };
    raster.gouraud(t, .{ .{ 10, 10 }, .{ 200, 10 }, .{ 10, 150 } }, .{ 0, 31 << 12, 0 }, 1, 31);
    try T.expectEqual(@as(u8, 1), pb[20 * 320 + 10]);
    try T.expect(pb[11 * 320 + 190] >= 28);
}
