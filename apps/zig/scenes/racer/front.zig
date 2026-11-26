// --------------------------------------------------------------------------
// RACER: the front end (M5 step 4): title -> track select -> race -> results -> select or title.
// The screens are states of the race FSM (fsm.zig: title, select, results), held by the game's
// session. While the title or the select shows, the game is in mode `off` (no race runs) and its
// FSM sits in that state; trackset.bindTo carries the FSM across a track load, so moving the cursor
// (which loads the track under it, for its outline and its look) keeps the screen.
//   title    fire / Enter: the select. Behind it the attract flyby of the track on show.
//   select   up / down: the cursor (loading that track; a file the loader refuses is marked bad and
//            named with its reason); fire / Enter: the race on it (refused, with a message, for a bad
//            file or a benchmark-only track); Backspace: the title.
//   grid     (a race's) Backspace: back to the select; so does Backspace in the bare benchmark view.
//   results  fire: the select; Backspace: the title; Enter / r: again (keys.zig, as in M3).
// Any other key on the title or the select (a digit, t, A-H, e, x, ...) leaves the front end for the
// bare benchmark view first, then does what it always did: every M1-M5 harness and board recipe
// starts with such a key, so they run exactly as before. Works on any Demo with `game`, `front`,
// `lib`, `which`, `recs`. Logs racer,front,<state> on every change of screen (off: none).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const clock = @import("clock.zig");
const fsm = @import("fsm.zig");
const minimap = @import("minimap.zig");
const seldraw = @import("seldraw.zig");
const trk = @import("trk.zig");

pub var break_results = false; // racer_front.mjs --break fsm (key V): the results' fire goes to the title

pub const Front = struct {
    cursor: usize = 0,
    frames: u32 = 0, // since the screen came up (the title's prompt blinks)
    logged: ?fsm.State = null, // null: no front-end screen (the benchmark view, a race, driving)
    msg: []const u8 = "", // why the last pick was refused
    map: minimap.Map = .{}, // the select's outline of the track on show
    map_for: ?usize = null, // ... built for this library entry
    lap_m: u32 = 0,
    clk: clock.Clock = .{ .start = 0, .extend = 0, .computed = true },
};

/// The front-end screen on show, or null.
pub fn screen(d: anytype) ?fsm.State {
    const g = &d.game;
    if (d.pose != null) return null;
    if (g.mode == .off and g.s.fsm.front()) return g.s.fsm.state;
    if (g.mode == .race and g.s.fsm.state == .results) return .results;
    return null;
}

/// The HUD's top line on the title and the select (null: the benchmark's line).
pub fn hudTop(d: anytype, buf: []u8) ?[]const u8 {
    const st = screen(d) orelse return null;
    return std.fmt.bufPrint(buf, "KESTREL RACING  {s}", .{if (st == .title) d.lib.list[d.which].label() else "TRACK SELECT"}) catch null;
}

pub fn hudBottom(d: anytype) ?[]const u8 {
    const st = screen(d) orelse return null;
    return if (st == .title) "FIRE: TRACKS   T: BENCH   O: OSD" else if (st == .select) "" else null;
}

/// A screen with no 3D under it (frontdraw.menuFrame): the select and the results.
pub fn menu(d: anytype) bool {
    const st = screen(d) orelse return false;
    return st != .title;
}

/// The cart's first screen.
pub fn boot(d: anytype) void {
    d.game.s.fsm = .{ .state = .title };
}

/// Once a frame: the log line on a change of screen, the race's records kept for its track, the select's outline.
pub fn update(d: anytype) void {
    const f = &d.front;
    const st = screen(d);
    if (st != f.logged) {
        zg.Console.log("racer,front,{s}", .{if (st) |s| @tagName(s) else "off"});
        f.logged = st;
        f.frames = 0;
    }
    f.frames +%= 1;
    if (st == .results) d.recs[d.which] = d.game.s.records;
    if (st == .select and f.map_for != d.which) {
        f.map = minimap.Map.fit(d.cur(), seldraw.MAP[2], seldraw.MAP[3]);
        f.lap_m = clock.lapLength(d.cur());
        f.clk = clock.of(d.cur());
        f.map_for = d.which;
    }
}

/// A key on a front-end screen; true: taken.
pub fn key(d: anytype, cp: u32) bool {
    const st = screen(d) orelse {
        if (cp != 8 or d.drive.mode != .off or d.game.s.fsm.state != .grid or d.game.mode == .bench) return false;
        d.pose = null; // a race's grid, or the bench view (its idle session sits on the grid): back to the select
        return toSelect(d, .back);
    };
    switch (cp) {
        13 => return switch (st) {
            .title => toSelect(d, .enter),
            .select => pick(d),
            else => false, // the results: Enter is "again" (keys.zig)
        },
        8 => return if (st == .results) toTitle(d) else fire(d, .back),
        'z', 'h', 'j', 'o', 'u', 'c', 'p', ' ', 0xE012, 'J', 'U', 'V' => return false, // audio, OSD, pause, quit, the --break keys: it stays
        else => {
            if (st != .results) d.game.setMode(.off); // a debug key: the bare benchmark view, then the key's own job
            return false;
        },
    }
}

/// The arrows and the joystick (0 up, 1 down, 2 left, 3 right, 5 fire) on a front-end screen; true: taken.
pub fn input(d: anytype, dir: u8) bool {
    const st = screen(d) orelse return false;
    switch (st) {
        .title => if (dir == 5) {
            _ = toSelect(d, .enter);
        },
        .select => switch (dir) {
            0 => move(d, d.lib.n - 1),
            1 => move(d, 1),
            5 => _ = pick(d),
            else => {},
        },
        .results => return dir == 5 and (if (break_results) toTitle(d) else toSelect(d, .enter)),
        else => return false,
    }
    return true;
}

fn fire(d: anytype, ev: fsm.Event) bool {
    d.game.s.fsm.fire(ev) catch return false; // WHY: an event the table refuses leaves the screen as it is
    return true;
}

/// Results / grid / title -> the select: the game leaves its race (its session keeps the FSM's new state).
fn toSelect(d: anytype, ev: fsm.Event) bool {
    if (!fire(d, ev)) return false;
    d.game.toFront();
    d.front.cursor = d.which;
    d.front.msg = "";
    return true;
}

fn toTitle(d: anytype) bool {
    if (!fire(d, .back)) return false;
    d.game.toFront();
    return true;
}

/// The cursor `step` entries on (mod the list), loading the track there unless it is marked bad.
fn move(d: anytype, step: usize) void {
    const f = &d.front;
    f.cursor = (f.cursor + step) % d.lib.n;
    f.msg = "";
    if (!d.lib.list[f.cursor].bad) d.setTrack(f.cursor); // a refusal marks it bad (its reason on screen)
}

/// Fire on the select: the race on the cursor's track, or the reason it cannot be raced.
fn pick(d: anytype) bool {
    const f = &d.front;
    const e = &d.lib.list[f.cursor];
    if (e.bad or f.cursor != d.which) {
        f.msg = "REFUSED FILE";
        return true;
    }
    if (d.cur().mood.flags & trk.BENCH_ONLY != 0) {
        f.msg = "NO RACE HERE";
        return true;
    }
    if (!fire(d, .pick)) return false;
    d.setGame(.race); // a fresh session on the grid: the state pick leads to
    return true;
}
