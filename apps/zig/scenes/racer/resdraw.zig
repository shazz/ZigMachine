// --------------------------------------------------------------------------
// RACER: the results screen (M5 step 4), once the race FSM reaches `results`: the final order (the
// standings: finishers by tick, then by track u), each car's livery swatch, name and finish time (DNF:
// not across the line), the player's best lap and which lap it was, the session's records on this
// track, and what to press. The top HUD line still says RESULTS (racehud.zig, pinned by racer_race).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const carmodel = @import("carmodel.zig");
const fd = @import("frontdraw.zig");
const menu = @import("menu.zig");
const palette = @import("palette.zig");
const racehud = @import("racehud.zig");
const standings = @import("standings.zig");

pub const FOOT = "FIRE:TRACKS ENTER:AGAIN BKSP:TITLE";
const PLACES = [8][]const u8{ "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH" };

pub fn draw(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    const s = &d.game.s;
    p.panel(16, 16, 288, 166);
    var b: [40]u8 = undefined;
    const head = std.fmt.bufPrint(&b, "RESULTS  {s}  {s}", .{ d.lib.list[d.which].label(), if (s.outcome == .win) "FINISH" else "TIME OVER" }) catch "";
    fd.text(os, fb, head, 24, 21, menu.HILITE);
    const u = s.us();
    var ord: [standings.MAXCARS]u8 = undefined;
    for (standings.order(&u, &s.finish, s.race.n, &ord), 0..) |k, place| row(os, fb, p, s, k, place);
    var t0: [12]u8 = undefined;
    var t1: [12]u8 = undefined;
    var t2: [12]u8 = undefined;
    const r = &s.rules;
    const best = if (r.best_i == 0) "-:--.-" else racehud.timeStr(&t0, r.best_t);
    fd.text(os, fb, std.fmt.bufPrint(&b, "BEST LAP {s}  LAP {}", .{ best, r.best_i }) catch "", 24, 132, palette.INK);
    const rec = &s.records;
    const lap = if (rec.best_lap == 0) "-:--.-" else racehud.timeStr(&t1, rec.best_lap);
    const race = if (rec.best_race == 0) "-:--.-" else racehud.timeStr(&t2, rec.best_race);
    fd.text(os, fb, std.fmt.bufPrint(&b, "RECORDS LAP {s} RACE {s}", .{ lap, race }) catch "", 24, 144, palette.INK);
    if (s.lap_record or s.race_record) fd.text(os, fb, "NEW RECORD", 24, 156, menu.HILITE);
    fd.text(os, fb, FOOT, 160 - FOOT.len * 4, 170, palette.INK);
}

/// One place: the place, the car's livery (body with its stripe), its name, its time.
fn row(os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px, s: anytype, k: u8, place: usize) void {
    const y: i32 = 34 + @as(i32, @intCast(place)) * 12;
    const ink = if (k == 0) menu.HILITE else palette.INK;
    fd.text(os, fb, PLACES[place], 24, y, ink);
    const l = carmodel.LIVERY[k];
    p.rect(60, y, 14, 8, 16 + l.body * 8 + 6);
    p.rect(60, y + 3, 14, 2, 16 + l.stripe * 8 + 6);
    var nb: [8]u8 = undefined;
    const name = if (k == 0) "YOU" else std.fmt.bufPrint(&nb, "CAR {}", .{k + 1}) catch "";
    fd.text(os, fb, name, 82, y, ink);
    var tb: [12]u8 = undefined;
    const t = s.finish[k];
    fd.text(os, fb, if (t == 0) "DNF" else racehud.timeStr(&tb, t), 220, y, ink);
}
