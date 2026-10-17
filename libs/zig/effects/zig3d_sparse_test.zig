// zig3d's two shortcuts (the sparse clip of a translating camera, and vertex
// aliases) against its general path: they must change no bit of any face.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const c3 = @import("zig3d.zig");

/// A ring of quads built facet by facet, as union_tnt3's ball is: every point
/// is held twice.
fn ring(verts: *[64]c3.Vec3, faces: *[16]c3.Face) void {
    for (0..16) |k| {
        const a = @as(f64, @floatFromInt(k)) * std.math.pi / 8.0;
        const b = @as(f64, @floatFromInt(k + 1)) * std.math.pi / 8.0;
        verts[4 * k + 0] = .{ .x = 80 * @cos(a), .y = 80 * @sin(a), .z = -40 };
        verts[4 * k + 1] = .{ .x = 80 * @cos(b), .y = 80 * @sin(b), .z = -40 };
        verts[4 * k + 2] = .{ .x = 80 * @cos(b), .y = 80 * @sin(b), .z = 40 };
        verts[4 * k + 3] = .{ .x = 80 * @cos(a), .y = 80 * @sin(a), .z = 40 };
        const i: u16 = @intCast(4 * k);
        faces[k] = .{ .v = .{ i, i + 1, i + 2, i + 3 }, .n = 4, .ink = @intCast(k) };
    }
}

test "aliases point each twin at the first copy, and -0 is not +0" {
    var verts: [64]c3.Vec3 = undefined;
    var faces: [16]c3.Face = undefined;
    ring(&verts, &faces);
    var buf: [64]u16 = undefined;
    const al = c3.aliases(&verts, &buf);
    try expectEqual(@as(u16, 0), al[0]);
    try expectEqual(@as(u16, 1), al[4]); // facet 1's first point is facet 0's second
    try expectEqual(@as(u16, 2), al[7]);
    const signed = [2]c3.Vec3{ .{ .x = 0, .y = 1, .z = 2 }, .{ .x = -0.0, .y = 1, .z = 2 } };
    var b2: [2]u16 = undefined;
    try expectEqual(@as(u16, 1), c3.aliases(&signed, &b2)[1]);
}

test "the sparse clip and the aliases give projectView's faces bit for bit" {
    var verts: [64]c3.Vec3 = undefined;
    var faces: [16]c3.Face = undefined;
    ring(&verts, &faces);
    var centroids: [16]c3.Vec3 = undefined;
    var buf: [64]u16 = undefined;
    const plain = c3.build(&verts, &faces, &centroids);
    var twins = plain;
    twins.alias = c3.aliases(&verts, &buf);
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    for ([_]c3.Vec3{ .{ .x = 0, .y = 70, .z = 100 }, .{ .x = 0, .y = 0, .z = 0 } }) |camera| {
        const fast = c3.View.init(&lens, camera);
        try std.testing.expect(fast.sparse);
        var slow = fast;
        slow.sparse = false;
        var s1: [64]c3.Screen = undefined;
        var s2: [64]c3.Screen = undefined;
        var o1: [16]c3.Poly = undefined;
        var o2: [16]c3.Poly = undefined;
        var rot = c3.Vec3{ .x = -std.math.pi / 2.0, .y = 0, .z = std.math.pi / 3.0 };
        var z: f64 = 0;
        for (0..300) |_| {
            const pos = c3.Vec3{ .x = 0, .y = 0, .z = z };
            const want = c3.projectView(&slow, pos, rot, &plain, &s1, &o1, .{});
            const got = c3.projectView(&fast, pos, rot, &twins, &s2, &o2, .{});
            try expectEqual(want.len, got.len);
            for (want, got) |a, b| try std.testing.expectEqualDeep(a, b);
            rot = .{ .x = rot.x + 0.033, .y = rot.y + 0.032, .z = rot.z + 0.031 };
            z = @max(z - 10, -700);
        }
    }
}
