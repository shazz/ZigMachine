// Native tests of GLENZ NEST (obj/nest.zig), the skin the solid modes keep
// to, and DOTS' depth ink (zig test apps/zig/scene_tests.zig).
const std = @import("std");
const T = std.testing;
const fx = @import("fixed3d.zig");
const fmesh = @import("fmesh.zig");
const nest = @import("nest.zig");
const xform = @import("xform.zig");

var mesh_buf: fmesh.Mesh = .{};
var frame_buf: xform.Frame = .{};

test "GLENZ NEST: four closed shells (Euler each), outward, corners on their radius" {
    const m = &mesh_buf;
    nest.build(m);
    try T.expectEqual(@as(u16, 60), m.nverts);
    try T.expectEqual(@as(u16, 104), m.nfaces);
    try T.expectEqual(@as(u16, 36), m.nskin);
    // V - E + F = 2 for each shell: dodecahedron 20 - 54 + 36, icosahedron
    // 12 - 30 + 20, dodecahedron again, cube 8 - 18 + 12
    try T.expectEqual(@as(u16, 54 + 30 + 54 + 18), m.nedges);
    for (m.edges[0..m.nedges]) |e| try T.expect(e.f1 != fmesh.NO_FACE);
    for (m.faces[0..m.nfaces], 0..) |f, i| {
        var c: [3]i32 = .{ 0, 0, 0 };
        for (0..3) |k| c[k] = @as(i32, m.verts[f.a][k]) + m.verts[f.b][k] + m.verts[f.c][k];
        try T.expect(fx.dot(m.faces[i].n, c) > 0);
    }
    for (m.verts[0..m.nverts], 0..) |v, i| {
        const shell: usize = if (i < 20) 0 else if (i < 32) 1 else if (i < 52) 2 else 3;
        const sq = @as(i32, v[0]) * v[0] + @as(i32, v[1]) * v[1] + @as(i32, v[2]) * v[2];
        const r = @sqrt(@as(f64, @floatFromInt(sq)));
        try T.expect(@abs(r - nest.RADII[shell] * 16384.0) < 2.0);
    }
}

test "GLENZ NEST: the solid modes see the skin only" {
    const m = &mesh_buf;
    nest.build(m);
    const fr = &frame_buf;
    const mat = fx.rotation(fx.angle(0.5), fx.angle(1.3), fx.angle(0.1));
    fr.transform(m, &mat, false);
    fr.cullSort(m, true, true);
    try T.expect(fr.nvis > 0 and fr.nvis < nest.SKIN);
    for (fr.recs[0..fr.nvis]) |r| try T.expect(r.a < 20 and r.b < 20 and r.c < 20); // dodecahedron corners
    fr.cullSort(m, false, false);
    try T.expectEqual(@as(u16, nest.SKIN), fr.nvis);
    fr.cullOnly(m);
    for (fr.vis[nest.SKIN..m.nfaces]) |v| try T.expect(!v);
}

test "GLENZ NEST: every corner stays in the object rows 24..175 at any turn" {
    const m = &mesh_buf;
    nest.build(m);
    const fr = &frame_buf;
    var a: u32 = 0;
    while (a < 4096) : (a += 1) { // three axes stepped at different rates
        const mat = fx.rotation(a *% (1 << 20), a *% (3 << 19), a *% (5 << 18));
        fr.transform(m, &mat, false);
        try T.expect(fr.box[1] >= 24 and fr.box[3] < 176 and fr.box[0] >= 0 and fr.box[2] < 320);
    }
}

test "DOTS ink: nearest at the white end of the ramp, farthest at its first step" {
    try T.expectEqual(@as(u8, xform.FLAT_LEVELS), xform.dotInk(-fx.ONE));
    try T.expectEqual(@as(u8, 1), xform.dotInk(fx.ONE));
    try T.expectEqual(@as(u8, 1), xform.dotInk(3 * fx.ONE));
    try T.expectEqual(@as(u8, xform.FLAT_LEVELS), xform.dotInk(-3 * fx.ONE));
    try T.expect(xform.dotInk(0) > 1 and xform.dotInk(0) < xform.FLAT_LEVELS);
}
