// RACER: the local-music cues (music.zig): each state's tune, benchmark silence, the toggle.
const std = @import("std");
const fsm = @import("fsm.zig");
const music = @import("music.zig");

const Cue = music.Cue;
fn ctx(state: fsm.State, ticks: u32) music.Ctx {
    return .{ .bench = false, .driving = false, .racing = true, .state = state, .ticks = ticks };
}

test "every race state has its tune; the start tune hands over to the loop" {
    try std.testing.expectEqual(Cue.title, music.cueFor(.{ .bench = false, .driving = false, .racing = false }));
    try std.testing.expectEqual(Cue.silent, music.cueFor(ctx(.grid, 0)));
    try std.testing.expectEqual(Cue.start, music.cueFor(ctx(.countdown, 10)));
    try std.testing.expectEqual(Cue.start, music.cueFor(ctx(.race, music.LOOP_AT - 1)));
    try std.testing.expectEqual(Cue.loop, music.cueFor(ctx(.race, music.LOOP_AT)));
    var fin = ctx(.finish, 5);
    fin.outcome = .win;
    try std.testing.expectEqual(Cue.win, music.cueFor(fin));
    fin.state = .results;
    try std.testing.expectEqual(Cue.win, music.cueFor(fin));
    fin.outcome = .timeout;
    try std.testing.expectEqual(Cue.result, music.cueFor(fin));
}

test "the benchmark laps and free driving are silent, whatever the state" {
    var c = ctx(.race, 400);
    c.bench = true;
    try std.testing.expectEqual(Cue.silent, music.cueFor(c));
    c.bench = false;
    c.driving = true;
    try std.testing.expectEqual(Cue.silent, music.cueFor(c));
}

test "the player asks once per change, and the toggle silences and restores" {
    var p = music.Player{ .songs = &music.SONGS };
    try std.testing.expectEqual(@as(?Cue, .start), p.step(ctx(.countdown, 0)));
    try std.testing.expectEqual(@as(?Cue, null), p.step(ctx(.countdown, 1)));
    try std.testing.expectEqual(@as(?Cue, .loop), p.step(ctx(.race, music.LOOP_AT)));
    p.toggle();
    try std.testing.expectEqual(@as(?Cue, .silent), p.step(ctx(.race, 301)));
    try std.testing.expectEqual(@as(?Cue, null), p.step(ctx(.race, 302)));
    p.toggle();
    try std.testing.expectEqual(@as(?Cue, .loop), p.step(ctx(.race, 303)));
}

test "every cue but silent names a racer_*.vgz file the song pack can find" {
    for (music.SONGS, 0..) |s, i| {
        if (i == 0) continue;
        try std.testing.expect(std.mem.startsWith(u8, s, "racer_") and std.mem.endsWith(u8, s, ".vgz"));
    }
}

test "the shipped table asks once for the race tune across start and loop, and names our kr_*.vgm files" {
    var p = music.Player{ .songs = &music.SHIPPED };
    try std.testing.expectEqual(@as(?Cue, .start), p.step(ctx(.countdown, 0)));
    try std.testing.expectEqual(@as(?Cue, null), p.step(ctx(.race, music.LOOP_AT))); // the same file: no reload
    try std.testing.expectEqualStrings("kr_race.vgm", p.name(.loop));
    for (music.SHIPPED[1..]) |s| try std.testing.expect(std.mem.startsWith(u8, s, "kr_") and std.mem.endsWith(u8, s, ".vgm"));
}

test "forget asks again for the same cue" {
    var p = music.Player{ .songs = &music.SHIPPED };
    _ = p.step(ctx(.race, 0));
    try std.testing.expectEqual(@as(?Cue, null), p.step(ctx(.race, 1)));
    p.forget();
    try std.testing.expectEqual(@as(?Cue, .start), p.step(ctx(.race, 2)));
}
