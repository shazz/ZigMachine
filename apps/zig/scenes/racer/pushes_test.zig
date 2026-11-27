// RACER: ARCADE car-vs-car at the drawn size (pushes.zig, R82 bug pass): the body is the model's footprint at the car
// scale, two overlapping cars are apart after one tick, a whole race keeps every pair apart (and --break push does not),
// CLASSIC has no body (freds72's contacts). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const carmodel = @import("carmodel.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const pushes = @import("pushes.zig");
const race = @import("race.zig");
const trk = @import("trk.zig");

fn arcadeRace(t: *const trk.Track) !race.Race {
    var r = try race.Race.init(t, race.NCARS);
    r.setModel(.arcade);
    r.pilot = true;
    return r;
}

/// The deepest overlap of any two cars of `r` (Q16).
fn worst(r: *const race.Race) i32 {
    var w: i32 = 0;
    for (r.cars[0..r.n], 0..) |*a, i| for (r.cars[i + 1 .. r.n]) |*b| {
        w = @max(w, pushes.overlap(a, b).depth);
    };
    return w;
}

test "the body is the drawn footprint: the GT's shadow box at the track's car scale; none in CLASSIC" {
    const t = try trk.parse(data.salt);
    var r = try arcadeRace(&t);
    const f = carmodel.gt.foot;
    const size: i64 = @as(i32, t.scale.car) << 8;
    const b = r.cars[3].body;
    try std.testing.expectEqual(@as(i32, @intCast(((@as(i64, f.x1 - f.x0) << 9) * size) >> 17)), b.hw);
    try std.testing.expect(b.hl > b.hw and b.hw > fix.lit(0.312)); // wider than freds72's collider: the car is drawn bigger
    r.setModel(.classic);
    try std.testing.expectEqual(pushes.Body{}, r.cars[3].body);
}

test "two cars side by side, overlapping by half a width: one tick of pushes and they are apart, moving apart" {
    const t = try trk.parse(data.salt);
    const r = try arcadeRace(&t);
    const a = r.cars[1];
    var b = r.cars[1];
    const right = a.axes().right;
    b.pos[0] += fix.mul(right[0], a.body.hw);
    b.pos[2] += fix.mul(right[2], a.body.hw);
    b.vel = .{ -right[0] >> 4, 0, -right[2] >> 4 }; // b drives into a
    var two = [2]@TypeOf(a){ a, b };
    try std.testing.expect(pushes.overlap(&two[0], &two[1]).depth > a.body.hw >> 1);
    _ = pushes.update(&two);
    try std.testing.expect(pushes.overlap(&two[0], &two[1]).depth <= 2);
    const rel = [2]i32{ two[1].vel[0] - two[0].vel[0], two[1].vel[2] - two[0].vel[2] };
    try std.testing.expect(fix.mul(rel[0], right[0]) + fix.mul(rel[1], right[2]) >= 0); // no longer closing
}

test "a race on Salt Flats (8 cars, the AI): no two cars ever drawn inside each other; --break push lets them" {
    const t = try trk.parse(data.salt);
    var w: [2]i32 = .{ 0, 0 };
    for (0..2) |k| {
        pushes.break_push = k == 1;
        defer pushes.break_push = false;
        var r = try arcadeRace(&t);
        for (0..1500) |_| {
            r.tick(0);
            w[k] = @max(w[k], worst(&r));
        }
    }
    const hw = (try arcadeRace(&t)).cars[0].body.hw;
    try std.testing.expect(w[0] < hw >> 3); // under an eighth of a half width: pixels, not a car inside another
    try std.testing.expect(w[1] > hw >> 1); // the mutant: freds72's player-only contacts let the AI cars overlap
}
