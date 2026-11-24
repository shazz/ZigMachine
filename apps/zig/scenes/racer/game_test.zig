// RACER: the race as the cart plays it: tick cadence, modes, the cars in the frame (liveries, the
// start grid in view, car-vs-car and car-vs-crest painter's order), the HUD words and the minimap.
// `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const crest = @import("crest.zig");
const car = @import("car.zig");
const carmodel = @import("carmodel.zig");
const data = @import("data.zig");
const fsm = @import("fsm.zig");
const game = @import("game.zig");
const ground = @import("ground.zig");
const minimap = @import("minimap.zig");
const racehud = @import("racehud.zig");
const testutil = @import("testutil.zig");
const trk = @import("trk.zig");

fn zero() u32 {
    return 0;
}

test "the grid waits; fire starts the countdown; a tick every second frame; the abort key is refused on the grid" {
    const t = try trk.parse(data.oval);
    var g = try game.Game.init(&t, zero);
    g.setMode(.race);
    for (0..20) |_| g.update();
    try std.testing.expectEqual(@as(u32, 0), g.s.fsm.ticks);
    g.again(); // nothing to abort
    try std.testing.expectEqual(fsm.State.grid, g.s.fsm.state);
    g.press(5, true);
    try std.testing.expectEqual(fsm.State.countdown, g.s.fsm.state);
    for (0..20) |_| g.update();
    try std.testing.expectEqual(@as(u32, 10), g.s.fsm.ticks);
    g.again();
    try std.testing.expectEqual(fsm.State.grid, g.s.fsm.state);
}

test "lap v2 starts by itself after 1 s on the grid, races on the recorded stream, and the round repeats every 2,880 frames" {
    const t = try trk.parse(data.oval);
    var g = try game.Game.init(&t, zero);
    g.setMode(.bench);
    for (0..game.GRID_FRAMES) |_| g.update();
    try std.testing.expectEqual(fsm.State.grid, g.s.fsm.state);
    g.update();
    try std.testing.expectEqual(fsm.State.countdown, g.s.fsm.state);
    for (0..game.ROUND_FRAMES - game.GRID_FRAMES - 1) |_| g.update();
    try std.testing.expectEqual(fsm.State.race, g.s.fsm.state);
    try std.testing.expectEqual(@as(u32, 1320), g.s.race.ticks);
    try std.testing.expect(g.s.race.cars[0].track.u > 119 << 16); // the player has completed lap 1
    g.update();
    try std.testing.expectEqual(fsm.State.grid, g.s.fsm.state); // the next round
    try std.testing.expectEqual(@as(u32, 0), g.s.race.ticks);
}

test "the start grid: all 8 cars are in view from the player's chase camera, the AI cars in their liveries, the player in red" {
    const t = try trk.parse(data.oval);
    var g = try game.Game.init(&t, zero);
    g.setMode(.race);
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    var cache = try testutil.newCache(carmodel.NV);
    defer std.testing.allocator.free(cache.e);
    const v = cam.view(g.pose());
    f.visibility(&t, &v, 5);
    f.collect(&t, &v, true);
    const before = f.stats.polys;
    g.drawCars(&f, &cache, &v, 5);
    try std.testing.expect(f.stats.polys - before >= 8 * 3); // at least three faces of every car
    var seen = [_]bool{false} ** 5;
    for (f.kept[before..f.stats.polys]) |r| {
        for (0..carmodel.LIVERIES) |k| {
            const base: u8 = 16 + (carmodel.RAMP_LIVERY + @as(u8, @intCast(k))) * 8;
            if (r.c >= base and r.c < base + 8) seen[k] = true;
        }
        if (r.c >= 16 + carmodel.RAMP_BODY * 8 and r.c < 16 + carmodel.RAMP_BODY * 8 + 8) seen[4] = true;
    }
    try std.testing.expectEqualSlices(bool, &.{ true, true, true, true, true }, &seen);
}

test "painter's order: a car past the crest is drawn BEFORE the crest's road (hidden), a car before it AFTER (seen)" {
    const t = try trk.parse(data.oval);
    var g = try game.Game.init(&t, zero);
    g.setMode(.race);
    const ci = crest.segment(&t);
    crest.setup(&g);
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    var cache = try testutil.newCache(carmodel.NV);
    defer std.testing.allocator.free(cache.e);
    const v = cam.view(g.pose());
    f.visibility(&t, &v, 8);
    f.collect(&t, &v, true);
    const crest_face = ground.findFace(&t, t.line[ci].pos, null).?.face;
    const crest_key = f.faceKey(crest_face).?;
    var near_min: u16 = 0xFFFF; // the car before the crest: its lowest key
    var far_max: u16 = 0; // the car past it: its highest key
    for ([_]usize{ 1, 2 }) |k| {
        const b = f.stats.polys;
        const c = &g.s.race.cars[k];
        @import("carview.zig").draw(&f, &cache, &v, g.shown(k), c.old, carmodel.liveryShift(k - 1));
        try std.testing.expect(f.stats.polys > b);
        for (f.key[b..f.stats.polys]) |key| {
            if (k == 1) near_min = @min(near_min, key) else far_max = @max(far_max, key);
        }
    }
    try std.testing.expect(far_max < crest_key); // past the crest: sorted before (under) the crest's road
    try std.testing.expect(near_min > crest_key); // before it: sorted after (over) it
}

test "car vs car: the nearer car's polygons are drawn after the farther one's, whatever the push order" {
    const t = try trk.parse(data.oval);
    var g = try game.Game.init(&t, zero);
    g.setMode(.race);
    for (3..8) |k| crest.place(&g, k, 60 + k);
    crest.place(&g, 0, 0);
    crest.place(&g, 1, 4); // far
    crest.place(&g, 2, 2); // near
    g.prev = g.cur;
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    var cache = try testutil.newCache(carmodel.NV);
    defer std.testing.allocator.free(cache.e);
    const v = cam.view(g.pose());
    f.visibility(&t, &v, 5);
    f.collect(&t, &v, true);
    const carview = @import("carview.zig");
    const b0 = f.stats.polys;
    carview.draw(&f, &cache, &v, g.shown(2), g.s.race.cars[2].old, 4); // the NEAR car first
    const b1 = f.stats.polys;
    carview.draw(&f, &cache, &v, g.shown(1), g.s.race.cars[1].old, 8); // then the far one
    const b2 = f.stats.polys;
    f.sort();
    var rank = try std.testing.allocator.alloc(u32, b2);
    defer std.testing.allocator.free(rank);
    for (f.order[0..b2], 0..) |idx, pos| rank[idx] = @intCast(pos);
    var near_min: u32 = 0xFFFFFFFF;
    var far_max: u32 = 0;
    for (b0..b1) |i| near_min = @min(near_min, rank[i]);
    for (b1..b2) |i| far_max = @max(far_max, rank[i]);
    try std.testing.expect(b1 > b0 and b2 > b1);
    try std.testing.expect(far_max < near_min);
}

test "HUD words: the time format and the line of every state" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("0:00.0", racehud.timeStr(&b, 0));
    try std.testing.expectEqualStrings("1:23.4", racehud.timeStr(&b, 2502));
    const t = try trk.parse(data.oval);
    var g = try game.Game.init(&t, zero);
    g.setMode(.race);
    try std.testing.expectEqualStrings("GRID  FIRE OR S TO START", racehud.top(&b, &g));
    g.go();
    for (0..40) |_| g.s.tick(0);
    try std.testing.expectEqualStrings("GET READY  2", racehud.top(&b, &g));
    for (0..50) |_| g.s.tick(0);
    try std.testing.expectEqualStrings("L1/3 0:00.0 B -:--.- 8TH", racehud.top(&b, &g));
    try std.testing.expect(racehud.top(&b, &g).len <= racehud.TOP_COLS);
    try std.testing.expectEqualStrings("0 KMH  TIME 75  GATE 0/4", racehud.bottom(&b, &g));
    g.s.fsm.state = .results;
    try std.testing.expectEqualStrings("ENTER OR R: AGAIN", racehud.bottom(&b, &g));
}

test "the minimap puts the player (white, 2 x 2) and the AI cars in the band's box and nowhere else; a far car is clamped" {
    const t = try trk.parse(data.oval);
    const m = minimap.Map.init(&t);
    var px = [_]u8{0} ** (320 * 12);
    var cars: [8][3]i32 = undefined;
    for (&cars, 0..) |*c, k| c.* = t.grid[k].pos;
    cars[7] = .{ 1 << 30, 0, 1 << 30 }; // far off the track: pinned to the box's edge, never out of it
    m.draw(&px, 320, &cars);
    var white: usize = 0;
    for (px, 0..) |c, i| {
        const x = i % 320;
        const y = i / 320;
        if (c != 0) try std.testing.expect(x >= minimap.X0 and x < minimap.X0 + minimap.W and y >= minimap.Y0 and y < minimap.Y0 + minimap.H);
        white += @intFromBool(c == 3);
    }
    try std.testing.expect(white >= 2 and white <= 4);
}
