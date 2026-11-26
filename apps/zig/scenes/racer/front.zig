// --------------------------------------------------------------------------
// RACER: the front end (M5 step 4, the M5 finish): title -> track select -> race -> results -> select
// or title, and the options screen from the title or the select. The screens are states of the race
// FSM (fsm.zig: title, select, options, results), held by the game's session. While a front-end screen
// shows, the game is in mode `off` (no race runs) and its FSM sits in that state; trackset.bindTo
// carries the FSM across a track load (a pick), so the screen is kept.
//   title    fire / Enter: the select; right: the options. Behind it the attract flyby of the track on show.
//   select   up / down: the cursor (nothing is loaded: the library's scan keeps each track's preview,
//            and a file the loader refused there is marked bad and named with its reason); fire /
//            Enter: the track loaded and raced (refused, with a message, for a bad file or a
//            benchmark-only track); right: the options; Backspace: the title.
//   options  up / down: the row; left / right (or fire / Enter): its value; BACK, or Backspace: the
//            screen it came from (options.zig).
//   grid     (a race's) Backspace: back to the select; so does Backspace in the bare benchmark view.
//   results  fire: the select; Backspace: the title; Enter / r: again (keys.zig, as in M3).
// Enter, Backspace and fire count once a press (press.zig: a held key's auto-repeat is dropped until
// its keyUp / inputRelease). Any other key on the title, the select or the options (a digit, t, A-H,
// e, x, ...) leaves the front end for the bare benchmark view first, then does what it always did:
// every M1-M5 harness and board recipe starts with such a key, so they run exactly as before. Works
// on any Demo with `game`, `front`, `lib`, `which`, `recs`. Logs racer,front,<state> on every change
// of screen (off: none).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const fsm = @import("fsm.zig");
const press = @import("press.zig");
const nav = @import("frontnav.zig");
const options = @import("options.zig");

pub var break_results = false; // racer_front.mjs --break fsm (key V): the results' fire goes to the title

pub const Front = struct {
    cursor: usize = 0,
    frames: u32 = 0, // since the screen came up (the title's prompt blinks)
    ticks: u32 = 0, // frames since boot (press.zig's clock)
    logged: ?fsm.State = null, // null: no front-end screen (the benchmark view, a race, driving)
    msg: []const u8 = "", // why the last pick was refused
    held: press.Held = .{},
    row: options.Row = .laps, // the options screen's cursor
    opt_from_title: bool = true, // where BACK leads
};

/// The front-end screen on show, or null.
pub fn screen(d: anytype) ?fsm.State {
    const g = &d.game;
    if (d.pose != null) return null;
    if (g.mode == .off and g.s.fsm.front()) return g.s.fsm.state;
    if (g.mode == .race and g.s.fsm.state == .results) return .results;
    return null;
}

/// The HUD's top line on the front end's screens (null: the benchmark's line).
pub fn hudTop(d: anytype, buf: []u8) ?[]const u8 {
    const st = screen(d) orelse return null;
    const what = switch (st) {
        .title => d.lib.list[d.which].label(),
        .options => "OPTIONS",
        else => "TRACK SELECT",
    };
    return std.fmt.bufPrint(buf, "KESTREL RACING  {s}", .{what}) catch null;
}

pub fn hudBottom(d: anytype) ?[]const u8 {
    const st = screen(d) orelse return null;
    return switch (st) {
        .title => "FIRE: TRACKS  RIGHT: OPTIONS  T: BENCH",
        .select, .options => "",
        else => null,
    };
}

/// A screen with no 3D under it (frontdraw.menuFrame): the select, the options and the results.
pub fn menu(d: anytype) bool {
    const st = screen(d) orelse return false;
    return st != .title;
}

/// The cart's first screen.
pub fn boot(d: anytype) void {
    @import("trackset.zig").cars(d); // the oval's cars (a CAR.KCR on the disk), then its look again: a car file's ramps
    @import("trackset.zig").look(d);
    d.game.s.fsm = .{ .state = .title };
}

/// Once a frame: the log line on a change of screen, the race's records kept for its track.
pub fn update(d: anytype) void {
    const f = &d.front;
    const st = screen(d);
    if (st != f.logged) {
        zg.Console.log("racer,front,{s}", .{if (st) |s| @tagName(s) else "off"});
        f.logged = st;
        f.frames = 0;
    }
    f.frames +%= 1;
    f.ticks +%= 1;
    if (st == .results) d.recs[d.which] = d.game.s.records;
}

/// A key's release (the cart's keyUp export).
pub fn keyUp(d: anytype, cp: u32) void {
    if (press.ofCode(cp)) |k| d.front.held.release(k);
}

/// A key on a front-end screen; true: taken. A held Enter / Backspace's repeat is taken and dropped anywhere.
pub fn key(d: anytype, cp: u32) bool {
    if (press.ofCode(cp)) |k| if (!d.front.held.press(k, d.front.ticks)) return true;
    const st = screen(d) orelse {
        if (cp != 8 or d.drive.mode != .off or d.game.s.fsm.state != .grid or d.game.mode == .bench) return false;
        d.pose = null; // a race's grid, or the bench view (its idle session sits on the grid): back to the select
        return nav.toSelect(d, .back);
    };
    switch (cp) {
        13 => return switch (st) {
            .title => nav.toSelect(d, .enter),
            .select => nav.pick(d),
            .options => nav.optFire(d),
            else => false, // the results: Enter is "again" (keys.zig)
        },
        8 => return switch (st) {
            .results => nav.toTitle(d),
            .options => nav.leaveOptions(d),
            else => nav.fire(d, .back),
        },
        'z', 'h', 'j', 'o', 'u', 'c', 'p', ' ', 0xE012, 'J', 'U', 'V', 'R', 'K' => return false, // audio, OSD, pause, quit, the --break keys: it stays
        else => {
            if (st != .results) d.game.setMode(.off); // a debug key: the bare benchmark view, then the key's own job
            return false;
        },
    }
}

/// The arrows and the joystick (0 up, 1 down, 2 left, 3 right, 5 fire) on a front-end screen; true: taken.
pub fn input(d: anytype, dir: u8) bool {
    const st = screen(d) orelse return false;
    if (dir == 5 and !d.front.held.press(.fire, d.front.ticks)) return true; // a held fire: once
    switch (st) {
        .title => switch (dir) {
            5 => _ = nav.toSelect(d, .enter),
            3 => _ = nav.toOptions(d, true),
            else => {},
        },
        .select => switch (dir) {
            0 => nav.move(d, d.lib.n - 1),
            1 => nav.move(d, 1),
            3 => _ = nav.toOptions(d, false),
            5 => _ = nav.pick(d),
            else => {},
        },
        .options => nav.optInput(d, dir),
        .results => return dir == 5 and (if (break_results) nav.toTitle(d) else nav.toSelect(d, .enter)),
        else => return false,
    }
    return true;
}

pub fn release(d: anytype, dir: u8) void {
    if (dir == 5) d.front.held.release(.fire);
}
