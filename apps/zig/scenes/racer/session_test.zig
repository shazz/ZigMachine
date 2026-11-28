// RACER: the race's rules, state machine, standings, records and a whole 3-lap race at the fixed
// input stream (the player's recorded autopilot). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const data = @import("data.zig");
const fsm = @import("fsm.zig");
const racefix = @import("racefix.zig");
const records = @import("records.zig");
const rules = @import("rules.zig");
const session = @import("session.zig");
const standings = @import("standings.zig");
const trk = @import("trk.zig");

const Fsm = fsm.Fsm;

test "the FSM: every legal transition in the table is taken, every other event is refused and changes nothing" {
    var legal: usize = 0;
    for (0..fsm.NSTATE) |s| {
        for (0..fsm.NEVENT) |e| {
            var m = Fsm{ .state = @enumFromInt(s), .ticks = 7 };
            const ev: fsm.Event = @enumFromInt(e);
            if (fsm.TABLE[s][e]) |to| {
                try m.fire(ev);
                try std.testing.expectEqual(to, m.state);
                try std.testing.expectEqual(@as(u32, 0), m.ticks);
                legal += 1;
            } else {
                try std.testing.expectError(error.IllegalTransition, m.fire(ev));
                try std.testing.expectEqual(@as(fsm.State, @enumFromInt(s)), m.state);
                try std.testing.expectEqual(@as(u32, 7), m.ticks);
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 21), legal); // 4 forward + 4 restarts + the front end's 6 (M5 step 4) + the options' 4 (M5 finish) + the car select's 3 (board batch)
}

test "the FSM walks grid -> countdown -> race -> finish -> results -> grid" {
    var m = Fsm{};
    for ([_]fsm.Event{ .start, .go, .finish, .done, .restart }) |ev| try m.fire(ev);
    try std.testing.expectEqual(fsm.State.grid, m.state);
}

test "rules: a checkpoint adds 10 s, the fourth closes a lap, the third lap wins; the lap times and the best lap are kept" {
    const t = try trk.parse(data.oval);
    var r = try rules.Rules.init(&t);
    try std.testing.expectEqual(rules.Result.none, r.tick(0));
    try std.testing.expectEqual(rules.START_TICKS - 1, r.remaining);
    const cps = t.checkpoints;
    var res: rules.Result = .none;
    for (0..rules.LAPS) |lap| {
        for (cps, 0..) |c, k| {
            for (0..100 + 10 * lap) |_| _ = r.tick(0);
            res = r.tick((@as(i32, @intCast(lap)) * 120 + @as(i32, @intCast(c)) + 1) << 16);
            if (k + 1 < cps.len) try std.testing.expectEqual(rules.Result.checkpoint, res);
        }
        try std.testing.expectEqual(if (lap + 1 == rules.LAPS) rules.Result.win else rules.Result.lap, res);
    }
    try std.testing.expectEqual(@as(u32, 1), r.best_i); // the first lap was the shortest
    try std.testing.expect(r.laps[0] < r.laps[1] and r.laps[1] < r.laps[2]);
    try std.testing.expectEqual(@as(i32, @intCast(r.finishU())), (3 * 120 - 1) << 16);
}

test "rules: the clock reaching zero is a timeout, judged before a checkpoint on the same tick" {
    const t = try trk.parse(data.oval);
    var r = try rules.Rules.init(&t);
    r.remaining = 1;
    try std.testing.expectEqual(rules.Result.timeout, r.tick(1000 << 16));
    var none = t;
    none.checkpoints = t.checkpoints[0..0];
    try std.testing.expectError(error.NoCheckpoints, rules.Rules.init(&none));
}

test "standings: finishers first by tick, then by u; ties go against the lower index (the player)" {
    const u = [_]i32{ 100, 100, 300, 200 };
    var fin = [_]u32{ 0, 0, 0, 0 };
    var o: [8]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 1, 0 }, standings.order(&u, &fin, 4, &o));
    fin = .{ 0, 50, 0, 40 }; // 3 then 1 finished: ahead of the faster 2, which has not
    try std.testing.expectEqualSlices(u8, &.{ 3, 1, 2, 0 }, standings.order(&u, &fin, 4, &o));
    try std.testing.expectEqual(@as(u32, 4), standings.place(0, &u, &fin, 4));
    try std.testing.expectEqual(@as(u32, 1), standings.place(3, &u, &fin, 4));
}

test "records: a better time is taken, an equal or worse or zero one is not" {
    var r = records.Records{};
    try std.testing.expect(r.offerLap(900));
    try std.testing.expect(!r.offerLap(900) and !r.offerLap(1000) and !r.offerLap(0));
    try std.testing.expect(r.offerLap(899));
    try std.testing.expectEqual(@as(u32, 899), r.best_lap);
    try std.testing.expect(r.offerRace(4000, 3) and !r.offerRace(4000, 3) and r.offerRace(4500, 5) and r.bestRace(3) == 4000);
}

test "a session: the grid waits, the countdown holds every car for 90 ticks, then the race runs" {
    const t = try trk.parse(data.oval);
    var s = try session.Session.init(&t);
    for (0..10) |_| s.tick(16);
    try std.testing.expectEqual(@as(u32, 0), s.race.ticks); // the grid does not tick the cars
    try s.start();
    try std.testing.expectError(error.IllegalTransition, s.start()); // already counting down
    for (0..session.COUNTDOWN_TICKS - 1) |_| s.tick(16);
    try std.testing.expectEqual(fsm.State.countdown, s.fsm.state);
    s.tick(16);
    try std.testing.expectEqual(fsm.State.race, s.fsm.state);
    try std.testing.expectEqual(@as(i32, 0), s.race.cars[0].vel[2]); // nobody has moved
    s.tick(16);
    try std.testing.expectEqual(@as(u32, 1), s.race.ticks);
    try std.testing.expectError(error.IllegalTransition, (blk: {
        var g = try session.Session.init(&t);
        break :blk g.restart();
    })); // nothing to abort on the grid
}

/// Play the fixed 3-lap race (the recorded autopilot) to the results; the session at the end.
fn playRace(t: *const trk.Track, buttons: []const u8) !session.Session {
    var s = try session.Session.init(t);
    try s.start();
    var k: usize = 0;
    while (s.fsm.state != .results) : (k += 1) {
        s.tick(if (s.race.ticks < buttons.len) buttons[s.race.ticks] else 0);
        if (k > 10_000) return error.RaceNeverEnds;
    }
    return s;
}

test "a 3-lap race at the fixed input: every car finishes, none leaves the asphalt or sticks to a wall for 2 s, the player wins, the order and times are pinned" {
    const t = try trk.parse(data.oval);
    const s = try playRace(&t, racefix.player_btn);
    try std.testing.expectEqual(rules.Result.win, s.outcome);
    try std.testing.expect(s.allFinished());
    try std.testing.expectEqual(@as(u32, 3726), s.finish[0]); // = the Lua's autopilot (race_full.bin's finish ticks)
    const fx = try racefix.crc();
    try std.testing.expectEqualSlices(u32, fx.finish, &s.finish);
    for (0..8) |k| {
        try std.testing.expect(s.watch.off_max[k] <= 2 * rules.HZ);
        try std.testing.expect(s.watch.wall_max[k] <= 2 * rules.HZ);
    }
    try std.testing.expectEqual(@as(u32, 1), s.playerPlace());
    try std.testing.expectEqual(@as(u32, RESULT_HASH), s.resultHash());
    try std.testing.expect(s.race_record);
    try std.testing.expectEqual(s.rules.best_t, s.records.best_lap);
    try std.testing.expectEqual(s.rules.total, s.records.bestRace(3));
}

const RESULT_HASH: u32 = 0xef4ce056; // CRC-32 of the final order and the eight finish ticks

test "a race with no input times out: the clock's 75 s are gone, the AI cars still run on to the cap" {
    const t = try trk.parse(data.oval);
    var s = try playRace(&t, &.{});
    try std.testing.expectEqual(rules.Result.timeout, s.outcome);
    try std.testing.expectEqual(@as(u32, 0), s.finish[0]);
    try std.testing.expect(s.playerPlace() >= 2);
    try s.restart();
    try std.testing.expectEqual(fsm.State.grid, s.fsm.state);
    try std.testing.expectEqual(@as(u32, 0), s.race.ticks);
}

test "the front end (M5 step 4): title -> select -> grid, results -> select or title, grid -> select; the race keys are refused there" {
    var m = Fsm{ .state = .title };
    try std.testing.expectError(error.IllegalTransition, m.fire(.pick)); // nothing picked on the title
    try std.testing.expectError(error.IllegalTransition, m.fire(.start));
    for ([_]fsm.Event{ .enter, .back, .enter, .pick }) |ev| try m.fire(ev); // title, select, title, select, grid
    try std.testing.expectEqual(fsm.State.grid, m.state);
    try m.fire(.back);
    try std.testing.expectEqual(fsm.State.select, m.state);
    try std.testing.expectError(error.IllegalTransition, m.fire(.restart)); // no race to abort on the select
    try std.testing.expect(m.front());
    m = .{ .state = .results };
    try m.fire(.enter);
    try std.testing.expectEqual(fsm.State.select, m.state);
    m = .{ .state = .results };
    try m.fire(.back);
    try std.testing.expectEqual(fsm.State.title, m.state);
    m = .{ .state = .race };
    try std.testing.expectError(error.IllegalTransition, m.fire(.back)); // mid-race: abort (restart) first
    try std.testing.expect(!m.front());
}
