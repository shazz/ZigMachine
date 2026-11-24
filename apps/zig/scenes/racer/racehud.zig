// --------------------------------------------------------------------------
// RACER: the race's two HUD text lines (the top band's 36 columns, the bottom band's 40), as pure
// functions of the game: no plane, no ZigOS import, so the native test pins the words and the
// headless harness pins the pixels. Times are ticks (30 Hz) shown as M:SS.T. The top line is the
// state's headline (the grid's prompt, the countdown, lap / time / best / place, the finish, the
// results); the bottom line is the speed, the clock, the checkpoint and what to press.
// --------------------------------------------------------------------------
const std = @import("std");
const fsm = @import("fsm.zig");
const game = @import("game.zig");
const rules = @import("rules.zig");
const session = @import("session.zig");
const vec = @import("vec.zig");

pub const TOP_COLS = 36; // the minimap owns the band's last four columns

/// M:SS.T of a tick count.
pub fn timeStr(buf: []u8, t: u32) []const u8 {
    const tenths = t * 10 / rules.HZ;
    return std.fmt.bufPrint(buf, "{}:{d:0>2}.{}", .{ tenths / 600, tenths / 10 % 60, tenths % 10 }) catch "?";
}

fn suffix(p: u32) []const u8 {
    return switch (p) {
        1 => "ST",
        2 => "ND",
        3 => "RD",
        else => "TH",
    };
}

pub fn top(buf: []u8, g: *const game.Game) []const u8 {
    const s = &g.s;
    const r = &s.rules;
    var t0: [12]u8 = undefined;
    var t1: [12]u8 = undefined;
    const place = s.playerPlace();
    const best: []const u8 = if (r.best_i == 0) "-:--.-" else timeStr(&t1, r.best_t);
    const total: []const u8 = if (s.finish[0] == 0) "DNF" else timeStr(&t0, s.finish[0]);
    const out = switch (s.fsm.state) {
        .grid => std.fmt.bufPrint(buf, "GRID  FIRE OR S TO START", .{}),
        .countdown => std.fmt.bufPrint(buf, "GET READY  {}", .{3 - s.fsm.ticks * 3 / session.COUNTDOWN_TICKS}),
        .race => std.fmt.bufPrint(buf, "L{}/{} {s} B {s} {}{s}", .{ r.nlaps + 1, rules.LAPS, timeStr(&t0, r.lap_t), best, place, suffix(place) }),
        .finish => std.fmt.bufPrint(buf, "{s}  {}{s}", .{ if (s.outcome == .win) "FINISH" else "TIME OVER", place, suffix(place) }),
        .results => std.fmt.bufPrint(buf, "RESULTS {}{s} {s}{s}", .{ place, suffix(place), total, if (s.race_record) " RECORD" else "" }),
    };
    return out catch "";
}

pub fn bottom(buf: []u8, g: *const game.Game) []const u8 {
    const s = &g.s;
    const r = &s.rules;
    const kmh = @as(u32, @intCast(@max(fixMul(vec.len(s.race.cars[0].vel), 900), 0)));
    const out = switch (s.fsm.state) {
        .grid => std.fmt.bufPrint(buf, "8 CARS  {} LAPS  CLOCK {}S +{}S A GATE", .{ rules.LAPS, rules.START_TICKS / rules.HZ, rules.EXTEND_TICKS / rules.HZ }),
        .countdown => std.fmt.bufPrint(buf, "ARROWS STEER  UP GAS  DOWN BRAKE", .{}),
        .race => std.fmt.bufPrint(buf, "{} KMH  TIME {}  GATE {}/{}{s}", .{ kmh, r.seconds(), r.checkpoint, r.checkpoints.len, if (r.extend_t > 0 and @mod(r.extend_t, 30) < 15) "  EXTEND TIME" else "" }),
        .finish => std.fmt.bufPrint(buf, "THE FIELD FINISHES  {}/{}", .{ done(s), s.race.n }),
        .results => std.fmt.bufPrint(buf, "ENTER OR R: AGAIN", .{}),
    };
    return out catch "";
}

fn fixMul(a: i32, k: i32) i32 {
    return @intCast((@as(i64, a) * k) >> 16);
}

fn done(s: *const session.Session) usize {
    var n: usize = 0;
    for (s.finish[0..s.race.n]) |f| n += @intFromBool(f != 0);
    return n;
}
