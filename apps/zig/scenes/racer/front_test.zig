// RACER M5 finish: the options screen's FSM edges, fresh presses (press.zig), the lap count (rules, records,
// a whole 1-lap race) and the track select's preview (preview.zig). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const clock = @import("clock.zig");
const data = @import("data.zig");
const fsm = @import("fsm.zig");
const minimap = @import("minimap.zig");
const press = @import("press.zig");
const preview = @import("preview.zig");
const racefix = @import("racefix.zig");
const records = @import("records.zig");
const rules = @import("rules.zig");
const session = @import("session.zig");
const trk = @import("trk.zig");

test "the options screen: title -options-> options -back-> title; select -options-> options -enter-> select; never from a race" {
    var m = fsm.Fsm{ .state = .title };
    try m.fire(.options);
    try std.testing.expectEqual(fsm.State.options, m.state);
    try std.testing.expect(m.front());
    try std.testing.expectError(error.IllegalTransition, m.fire(.pick)); // nothing is raced from the options
    try std.testing.expectError(error.IllegalTransition, m.fire(.options));
    try m.fire(.back);
    try std.testing.expectEqual(fsm.State.title, m.state);
    m = .{ .state = .select };
    try m.fire(.options);
    try m.fire(.enter);
    try std.testing.expectEqual(fsm.State.select, m.state);
    for ([_]fsm.State{ .grid, .countdown, .race, .finish, .results }) |s| {
        m = .{ .state = s };
        try std.testing.expectError(error.IllegalTransition, m.fire(.options));
    }
}

test "fresh presses: a held key's repeats are dropped until it comes up; a key with no event for TIMEOUT frames is up" {
    var h = press.Held{};
    try std.testing.expect(h.press(.enter, 10)); // the first press
    try std.testing.expect(!h.press(.enter, 40)); // the host's repeat 500 ms later
    for (41..200) |f| try std.testing.expect(!h.press(.enter, @intCast(f))); // repeats every frame: still held
    h.release(.enter);
    try std.testing.expect(h.press(.enter, 201)); // up, then down: fresh
    try std.testing.expect(h.press(.backspace, 202)); // keys are apart
    try std.testing.expect(!h.press(.backspace, 202 + press.TIMEOUT)); // no keyUp, but within the timeout: a repeat
    try std.testing.expect(h.press(.fire, 0));
    try std.testing.expect(h.press(.fire, press.TIMEOUT + 1)); // no release and no event for TIMEOUT frames: up
    try std.testing.expectEqual(@as(?press.Key, .enter), press.ofCode(13));
    try std.testing.expectEqual(@as(?press.Key, .backspace), press.ofCode(8));
    try std.testing.expectEqual(@as(?press.Key, null), press.ofCode('t'));
}

test "fresh presses: the mutant (--break repeat) takes every repeat" {
    var h = press.Held{};
    press.break_repeat = true;
    defer press.break_repeat = false;
    try std.testing.expect(h.press(.enter, 1) and h.press(.enter, 2));
}

test "laps: the options' 1 / 3 / 5 wrap both ways; an unknown count restarts from 3" {
    try std.testing.expectEqual(@as(u32, 5), rules.nextLaps(3, 1));
    try std.testing.expectEqual(@as(u32, 1), rules.nextLaps(5, 1));
    try std.testing.expectEqual(@as(u32, 5), rules.nextLaps(1, -1));
    try std.testing.expectEqual(@as(u32, 1), rules.nextLaps(3, -1));
    try std.testing.expectEqual(@as(u32, 5), rules.nextLaps(4, 1));
}

test "records: the best race is kept per lap count, the best lap across them" {
    var r = records.Records{};
    try std.testing.expect(r.offerRace(3000, 3));
    try std.testing.expect(r.offerRace(1000, 1)); // a shorter race is not a better 3-lap race
    try std.testing.expectEqual(@as(u32, 3000), r.bestRace(3));
    try std.testing.expectEqual(@as(u32, 1000), r.bestRace(1));
    try std.testing.expectEqual(@as(u32, 0), r.bestRace(5));
    try std.testing.expect(!r.offerRace(0, 3));
}

test "a 1-lap race at the fixed input: the player wins after one lap, the finish line is lap 1's last checkpoint" {
    const t = try trk.parse(data.oval);
    var s = try session.Session.init(&t);
    s.laps = 1;
    s.reset(); // the length is kept across a reset (Game.setMode sets it, then resets)
    try std.testing.expectEqual(@as(u32, 1), s.rules.goal);
    const last: i32 = @intCast(t.checkpoints[t.checkpoints.len - 1]);
    try std.testing.expectEqual(last << 16, s.rules.finishU());
    try s.start();
    var k: usize = 0;
    while (s.fsm.state != .finish and s.fsm.state != .results) : (k += 1) {
        s.tick(if (s.race.ticks < racefix.player_btn.len) racefix.player_btn[s.race.ticks] else 0);
        if (k > 10_000) return error.RaceNeverEnds;
    }
    try std.testing.expectEqual(rules.Result.win, s.outcome);
    try std.testing.expectEqual(@as(u32, 1), s.rules.nlaps);
    try std.testing.expectEqual(s.rules.total, s.records.bestRace(1));
    try std.testing.expectEqual(@as(u32, 0), s.records.bestRace(3));
}

test "the select's preview: the outline, lap length, clock and name of a track it has not loaded = the loaded track's" {
    const t = try trk.parse(data.oval);
    const p = preview.Preview.of(&t);
    try std.testing.expect(p.ready and !p.bench_only);
    try std.testing.expectEqual(clock.lapLength(&t), p.lap_m);
    try std.testing.expectEqual(clock.of(&t), p.clk());
    try std.testing.expectEqualStrings(std.mem.sliceTo(&t.name, 0), p.label());
    const m = minimap.Map.fit(&t, preview.BOX[0], preview.BOX[1]);
    try std.testing.expectEqual(m.n, p.map.n);
    try std.testing.expectEqualSlices([2]u8, m.pts[0..m.n], p.map.pts[0..p.map.n]);
    clock.break_flat = true; // the --break clock key works after the scan: the clock is computed when shown
    defer clock.break_flat = false;
    try std.testing.expectEqual(@as(u32, clock.BASE_START * clock.HZ), p.clk().start);
    try std.testing.expect(!(preview.Preview{}).ready);
}
