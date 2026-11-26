// RACER: the ARCADE physics (R82 32X feel, FEEL.md): the engine against its Python twin (tools/racer/feel.py's pins in
// feel_params.zig), the pedals, the off-road drag, the walls, a race of 8 arcade cars, and the CLASSIC path untouched.
// `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const arcade = @import("arcade.zig");
const arcar = @import("arcadecar.zig");
const car = @import("car.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const npc = @import("npc.zig");
const params = @import("feel_params.zig");
const race = @import("race.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const wall = @import("wall.zig");

/// feel.py's `run`: the speed after each tick, the throttle held (ramping in) or released.
fn run(b: *const params.Block, out: []i32, s0: i32, held: bool, off: u2) void {
    var s = s0;
    var thr: i32 = 0;
    for (out) |*o| {
        thr = arcade.pedal(thr, held);
        s = arcade.speed(b, s, thr, 0, off);
        o.* = s;
    }
}

fn ticksTo(trace: []const i32, kmh: i64) u32 {
    for (trace, 1..) |s, i| if (@as(i64, s) * 900 >= kmh << 16) return @intCast(i);
    return 0;
}

test "every class's straight line and coast-down = the Python twin's pins (ticks to 100 / 200 km/h, both traces' CRC)" {
    var up: [params.PIN_TICKS]i32 = undefined;
    var down: [params.PIN_TICKS]i32 = undefined;
    for (&params.CLASSES, params.PINS) |*b, p| {
        run(b, &up, 0, true, arcade.OFF_NONE);
        run(b, &down, b.top, false, arcade.OFF_NONE);
        try std.testing.expectEqual(p.to100, ticksTo(&up, 100));
        try std.testing.expectEqual(p.to200, ticksTo(&up, 200));
        try std.testing.expectEqual(p.up, std.hash.crc.Crc32IsoHdlc.hash(std.mem.sliceAsBytes(&up)));
        try std.testing.expectEqual(p.down, std.hash.crc.Crc32IsoHdlc.hash(std.mem.sliceAsBytes(&down)));
        try std.testing.expect(up[up.len - 1] <= b.top and up[up.len - 1] > b.top - (b.top >> 5)); // the top, never past it
    }
}

test "off the road: three or four wheels off settle slower than one or two, both under the top; never below 0" {
    const b = &params.CLASSES[0];
    var full: [900]i32 = undefined;
    var half: [900]i32 = undefined;
    run(b, &full, b.top, true, arcade.OFF_FULL);
    run(b, &half, b.top, true, arcade.OFF_HALF);
    try std.testing.expect(full[899] < half[899] and half[899] < b.top - (b.top >> 3));
    try std.testing.expect(full[0] >= b.top - @divTrunc(b.max_dec + 255, 256)); // the deceleration is capped
    try std.testing.expectEqual(@as(i32, 0), arcade.speed(b, 10, 0, 256, arcade.OFF_FULL)); // the brake stops, never reverses
}

test "the pedals ramp 0..256 a step a tick and the brake releases the throttle" {
    var e = arcade.Engine{};
    for (0..20) |_| e.press(true, false);
    try std.testing.expectEqual(@as(i32, 256), e.thr);
    e.press(true, true);
    try std.testing.expectEqual(@as(i32, 256 - arcade.PEDAL), e.thr);
    try std.testing.expectEqual(arcade.PEDAL, e.brake);
    for (0..20) |_| e.press(false, false);
    try std.testing.expectEqual(@as(i32, 0), e.thr + e.brake);
}

test "the engine note rises through each gear and drops at a shift" {
    const b = &params.CLASSES[0];
    var last: i32 = 0;
    var drops: u32 = 0;
    var s: i32 = 0;
    while (s < b.top) : (s += 64) {
        const r = arcade.rpm(b, s);
        if (r < last) drops += 1;
        try std.testing.expect(r > 0 and r <= arcade.MAX_RPM);
        last = r;
    }
    try std.testing.expectEqual(@as(u32, 5), drops);
}

fn arcadeRace(t: *const trk.Track) !race.Race {
    var r = try race.Race.init(t, race.NCARS);
    r.setModel(.arcade);
    r.pilot = true;
    return r;
}

test "the racing line's heading is the car's: forward along it" {
    const t = try trk.parse(data.oval);
    const r = try arcadeRace(&t);
    var c = r.cars[0];
    for ([_]i32{ 0, 30, 60, 90 }) |i| {
        c.angle = wall.lineYaw(&c, i);
        const a = @import("seg.zig").corners(&t, i);
        const b = @import("seg.zig").corners(&t, i + 1);
        const d = vec.normz(vec.between(vec.lerp(a.l, a.r, fix.ONE / 2), vec.lerp(b.l, b.r, fix.ONE / 2)));
        try std.testing.expect(vec.dot(c.axes().fwd, d) > fix.lit(0.99));
    }
}

test "a wall: rolled back, turned onto the line and slowed; a hard crash puts the car back on the line, stopped" {
    const t = try trk.parse(data.oval);
    var r = try arcadeRace(&t);
    const c = &r.cars[0];
    const yaw = wall.lineYaw(c, c.track.segment);
    c.angle = yaw +% fix.lit(0.06); // ~22 degrees: a glancing hit, under the crash angle
    const start = c.pos;
    c.vel = vec.scale(c.axes().fwd, fix.lit(0.1));
    var hit = false;
    for (0..200) |_| {
        const h = c.hits;
        c.prepare();
        c.integrate();
        c.update();
        if (c.hits != h) {
            hit = true;
            break;
        }
        c.vel = vec.scale(c.axes().fwd, fix.lit(0.1)); // straight into the wall
    }
    try std.testing.expect(hit and c.angle == wall.lineYaw(c, c.track.segment) and c.crashes == 0);
    try std.testing.expect(vec.dot(c.vel, c.vel) < fix.mul(fix.lit(0.1), fix.lit(0.1)) and !std.meta.eql(start, c.pos));
    c.angle +%= fix.lit(0.2); // ~72 degrees at speed: a crash
    c.vel = vec.scale(c.axes().fwd, wall.CRASH_SPEED + fix.lit(0.05));
    for (0..100) |_| {
        c.prepare();
        c.integrate();
        c.update();
        if (c.crashes > 0) break;
    }
    try std.testing.expectEqual(@as(u32, 1), c.crashes);
    try std.testing.expectEqual(vec.V{ 0, 0, 0 }, c.vel);
}

test "an arcade race on the oval: 8 cars round for 2,400 ticks on the AI's controller, none stuck, a pin of its state" {
    const t = try trk.parse(data.oval);
    var r = try arcadeRace(&t);
    for (0..2400) |_| r.tick(0);
    for (&r.cars) |*c| try std.testing.expect(c.track.u > 60 << 16); // half a lap at least
    try std.testing.expect(r.cars[0].hits < 400);
    try std.testing.expectEqual(@as(u32, 0xb3387a6f), r.crc()); // the Zig model is the arcade's oracle (FEEL.md): this pins it
}

test "an arcade race on Salt Flats (its world and car scales, its cues): the AI round 3 laps in 100 s without a crash" {
    const t = try trk.parse(data.salt);
    try std.testing.expect(t.scale.world > trk.SCALE_ONE and t.scale.car > trk.SCALE_ONE);
    var r = try arcadeRace(&t);
    for (0..3000) |_| r.tick(0);
    const n: i32 = @intCast(t.lr.len);
    for (&r.cars) |*c| {
        try std.testing.expect(c.track.u > 3 * n << 16);
        try std.testing.expectEqual(@as(u32, 0), c.crashes);
    }
}

test "a track file's scales: absent = 1, a 36-byte mood block read, one out of range refused (BadMood)" {
    const o = try trk.parse(data.oval);
    try std.testing.expectEqual(trk.Scale{}, o.scale);
    const s = try trk.parse(data.salt);
    try std.testing.expect(s.scale.world != trk.SCALE_ONE);
    var bad: [data.salt.len]u8 align(4) = undefined;
    @memcpy(&bad, data.salt);
    std.mem.writeInt(u16, bad[bad.len - 4 ..][0..2], 9999, .little); // the world scale, past 16
    const crc = std.hash.crc.Crc32IsoHdlc.hash(bad[trk.HEADER..]);
    std.mem.writeInt(u32, bad[8..12], crc, .little);
    try std.testing.expectError(error.BadMood, trk.parse(&bad));
}

test "the classic race is untouched by an arcade one's existence: the default model, no world or size" {
    const t = try trk.parse(data.oval);
    const r = try race.Race.init(&t, race.NCARS);
    for (r.cars) |c| try std.testing.expect(c.model == .classic and c.world == fix.ONE and c.size == fix.ONE);
}

test "sub-steps: a tick's displacement is cut under STEP, at most MAX_STEPS" {
    try std.testing.expectEqual(@as(u32, 1), arcar.steps(.{ fix.lit(0.1), 0, fix.lit(0.1) }));
    try std.testing.expectEqual(@as(u32, 4), arcar.steps(.{ fix.lit(1.3), 0, 0 }));
    try std.testing.expectEqual(arcar.MAX_STEPS, arcar.steps(.{ 100 << 16, 0, 0 }));
}

test "the AI's cues: 0 is none (freds72's brake rule), else the car holds SKILL of the cue's speed" {
    const t = try trk.parse(data.salt);
    try std.testing.expect(trk.cue(&t, 0) != 0 or trk.cue(&t, 1) != 0); // the Track Kit baked them
    const o = try trk.parse(data.oval);
    var r = try arcadeRace(&o);
    const c = &r.cars[1];
    npc.arcadePedals(c, true); // no cues on the oval: the steer-hard rule brakes
    try std.testing.expect(c.eng.brake > 0 and c.eng.thr == 0);
}
