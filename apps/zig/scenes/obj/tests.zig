// Native tests of the OBJ demo's integer 3D (zig test apps/zig/scene_tests.zig).
const std = @import("std");
const fx = @import("fixed3d.zig");
const fmesh = @import("fmesh.zig");
const sphere = @import("sphere.zig");
const raster = @import("raster.zig");
const xform = @import("xform.zig");
const fdiv = @import("fdiv.zig");

test "fdiv: floor division by the reciprocal table is exact" {
    var n: i32 = -40000;
    while (n <= 40000) : (n += 7) {
        var d: i32 = 1;
        while (d < 300) : (d += 1) {
            const qr = fdiv.floorDivRem(n, d);
            try T.expectEqual(@divFloor(n, d), qr.q);
            try T.expectEqual(n - qr.q * d, qr.r);
        }
    }
}
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
        for (m.faces[0..m.nfaces]) |f| try T.expect(f.inward == 0);
        for (m.faces[0..m.nfaces], 0..) |f, i| { // each normal points away from the centre
            var c: [3]i32 = .{ 0, 0, 0 };
            for (0..3) |k| c[k] = @as(i32, m.verts[f.a][k]) + m.verts[f.b][k] + m.verts[f.c][k];
            try T.expect(fx.dot(m.faces[i].n, c) > 0);
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
        for (m.faces[0..m.nfaces]) |f| inward += f.inward;
        try T.expect(inward == 0 or inward == m.nfaces); // one winding per file
        for (m.faces[0..m.nfaces], 0..) |f, i| {
            var c: [3]i32 = .{ 0, 0, 0 };
            for (0..3) |k| c[k] = @as(i32, m.verts[f.a][k]) + m.verts[f.b][k] + m.verts[f.c][k];
            try T.expect(fx.dot(m.faces[i].n, c) > 0);
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
            m.verts[m.nverts][3] = 0;
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
    const mat = fx.rotation(fx.angle(0.3), fx.angle(1.1), fx.angle(0.2));
    fr.transform(m, &mat, false);
    var seen: u32 = 0;
    for (0..m.nfaces) |i| {
        const f = m.faces[i];
        const n = fx.apply(&mat, m.faces[i].n);
        var look: i64 = 0; // n . (centre - eye), the eye at z = -DIST
        for (0..3) |k| {
            const c = @divTrunc(fx.apply(&mat, m.verts[f.a])[k] + fx.apply(&mat, m.verts[f.b])[k] + fx.apply(&mat, m.verts[f.c])[k], 3);
            look += @as(i64, n[k]) * (c + if (k == 2) fx.DIST else 0);
        }
        if (@abs(look) < 4000 * 16384) continue; // grazing: rounding decides
        try T.expectEqual(look < 0, fr.facing(m, i));
        if (fr.facing(m, i)) seen += 1;
    }
    try T.expect(seen > m.nfaces / 4);
}

test "cullSort: far first by depth bucket, every face once, flat shades in range" {
    const m = &mesh_buf;
    sphere.build(m, sphere.LEVELS[6]);
    const fr = &frame_buf;
    const mat = fx.rotation(fx.angle(0.7), fx.angle(0.4), 0);
    fr.transform(m, &mat, false);
    fr.cullSort(m, false, true);
    try T.expectEqual(m.nfaces, fr.nvis);
    var last: i32 = std.math.minInt(i32);
    var sum: u64 = 0;
    for (fr.recs[0..fr.nvis]) |r| {
        const z = (60000 - (fr.pv[r.a].z + fr.pv[r.b].z + fr.pv[r.c].z)) >> 8; // the bucket
        try T.expect(z >= last);
        try T.expect(r.shade >= 1 and r.shade <= xform.FLAT_LEVELS - 1);
        last = z;
        sum += @as(u64, r.a) + r.b + r.c;
    }
    var want: u64 = 0;
    for (m.faces[0..m.nfaces]) |f| want += @as(u64, f.a) + f.b + f.c;
    try T.expectEqual(want, sum);
}
