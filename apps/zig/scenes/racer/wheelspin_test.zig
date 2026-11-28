// RACER: the turning wheels (wheelspin.zig, board batch item 3) on the built-in GT.
const std = @import("std");
const carmodel = @import("carmodel.zig");
const ws = @import("wheelspin.zig");
const trk = @import("trk.zig");

const gt = &carmodel.gt;
var vs: [ws.MAX_VERTS]trk.Vert = undefined;
var fs: [ws.MAX_FACES]trk.Face = undefined;

fn wheelIds() []const trk.Face {
    return gt.range(.wheels);
}

test "the GT's wheels fall in four groups: left / right, rear / front, each centre on its side and axle" {
    const g = &gt.spin;
    try std.testing.expect(g.any);
    try std.testing.expect(g.centre[0][0] < 0 and g.centre[1][0] > 0 and g.centre[2][0] < 0 and g.centre[3][0] > 0);
    try std.testing.expect(g.centre[2][2] > g.centre[0][2] and g.centre[3][2] > g.centre[1][2]); // the front axle ahead
    for (wheelIds()) |f| for (f.v[0..f.nv]) |id| try std.testing.expect(g.of[id] != ws.NONE);
    for (gt.range(.hull)) |f| for (f.v[0..f.nv]) |id| try std.testing.expect(g.of[id] == ws.NONE);
}

test "at rest (no spin, no steer) the model's own faces are drawn" {
    try std.testing.expect(ws.pose(&gt.spin, gt.verts, wheelIds(), 0, 0, &vs, &fs) == null);
}

test "a spin turns each wheel vertex about its axle: its distance from it kept, the body untouched, the faces still planar" {
    const faces = ws.pose(&gt.spin, gt.verts, wheelIds(), 0x2000_0000, 0, &vs, &fs).?; // an eighth of a turn
    var moved: u32 = 0;
    for (gt.verts, 0..) |v, id| {
        const k = gt.spin.of[id];
        if (k == ws.NONE) {
            try std.testing.expectEqual(v, vs[id]);
            continue;
        }
        const c = gt.spin.centre[k];
        const r0 = (v[1] - c[1]) * (v[1] - c[1]) + (v[2] - c[2]) * (v[2] - c[2]);
        const r1 = (vs[id][1] - c[1]) * (vs[id][1] - c[1]) + (vs[id][2] - c[2]) * (vs[id][2] - c[2]);
        try std.testing.expect(@abs(r1 - r0) <= 4 * @as(i32, @intCast(std.math.sqrt(@as(u32, @intCast(r0))))) + 4);
        try std.testing.expectEqual(v[0], vs[id][0]); // a spin never moves a wheel sideways
        if (v[1] != vs[id][1] or v[2] != vs[id][2]) moved += 1;
    }
    try std.testing.expect(moved > 0);
    for (faces) |f| for (f.v[0..f.nv]) |id| { // every vertex on its face's turned plane (a Q14 normal times a 1-unit error)
        const d = @as(i64, f.n[0]) * vs[id][0] + @as(i64, f.n[1]) * vs[id][1] + @as(i64, f.n[2]) * vs[id][2] - f.cp;
        try std.testing.expect(@abs(d) <= 3 * 16384);
    };
}

test "a steer turns only the front wheels" {
    _ = ws.pose(&gt.spin, gt.verts, wheelIds(), 0, 0x0800_0000, &vs, &fs).?;
    var front_moved = false;
    for (gt.verts, 0..) |v, id| {
        const k = gt.spin.of[id];
        if (k == ws.NONE or k & 2 == 0) {
            try std.testing.expectEqual(v, vs[id]);
        } else if (v[0] != vs[id][0] or v[2] != vs[id][2]) front_moved = true;
    }
    try std.testing.expect(front_moved);
}

test "no wheels part, or a part past the scratch, is not posed (the model's own faces, never an overrun)" {
    const none = ws.groups(gt.verts, &.{});
    try std.testing.expect(!none.any);
    try std.testing.expect(ws.pose(&none, gt.verts, &.{}, 0x1000_0000, 0, &vs, &fs) == null);
    const many: [ws.MAX_FACES + 1]trk.Face = @splat(gt.range(.wheels)[0]);
    try std.testing.expect(ws.pose(&gt.spin, gt.verts, &many, 0x1000_0000, 0, &vs, &fs) == null);
}

test "a car's snapshot: the spin is its wheel turns / 64, the steer half its angle" {
    const w = ws.ofCar(64 << 16, 1 << 15); // 64 wheel turns, a steer of 0.5 turn (out of range: only the maths is checked)
    try std.testing.expectEqual(@as(u32, 0), w[0]); // one whole drawn turn
    try std.testing.expectEqual(@as(u32, 0x4000_0000), w[1]); // a quarter turn
    try std.testing.expectEqual(@as(u32, 0x8000_0000), ws.ofCar(32 << 16, 0)[0]);
}
