// --------------------------------------------------------------------------
// RACER: the options screen's values (M5 finish), reached from the title or the track select (the
// right arrow / joystick right) and kept for the session (RAM only, as the records: Q6). Each row is
// a setting the debug keys already change, so the two stay one state: what a key changes the screen
// shows, and the other way round.
//   LAPS           1 / 3 / 5 (rules.race_laps: a race's length; the bench laps keep the reference's 3)
//   SHADOW         REAL / CHECKERBOARD (shadow.fake, key y)
//   SHADING        FLAT / LIT / SOFT (project.shade, key i)
//   DRAW DISTANCE  3..8 tiles (Demo.play_r, keys 3-8; a bench lap still pins its own 5)
//   MUSIC          ON / OFF (the music player, key z)
//   HAZE           ON / OFF (M6: haze.on, key q; NONE on a track whose mood has no haze, NO ROOM where it does not fit)
//   PHYSICS        ARCADE / CLASSIC (R82 32X feel: arcade.model, key T; FEEL.md)
//   CAR CLASS      FORMULA / STOCK / PROTO (the arcade engine's class, key M)
//   (SHADOW also offers REAL HEADROOM on a track whose import kept one: project.headroom, key 9)
//   BACK           to the screen it came from
// Works on any Demo with `play_r`, `r`, `audio`, `drive`, `game` and trackset's look. Logs
// racer,option,<row>,<value> on every change.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const project = @import("project.zig");
const rules = @import("rules.zig");
const shadow = @import("shadow.zig");
const ts = @import("trackset.zig");
const haze = @import("haze.zig");
const arcade = @import("arcade.zig");
const params = @import("feel_params.zig");

pub const Row = enum(u8) { laps, shadow, shading, distance, music, haze, physics, class, back };
pub const ROWS = @typeInfo(Row).@"enum".fields.len;
pub const R_MIN = 3;
pub const R_MAX = 8;

pub const LABELS = [ROWS][]const u8{ "LAPS", "SHADOW", "SHADING", "DRAW DISTANCE", "MUSIC", "HAZE", "PHYSICS", "CAR CLASS", "BACK" };

/// A row's value as the screen shows it ("" for BACK).
pub fn value(d: anytype, r: Row, buf: []u8) []const u8 {
    return switch (r) {
        .laps => std.fmt.bufPrint(buf, "{}", .{rules.race_laps}) catch "",
        .shadow => if (shadow.fake) "CHECKERBOARD" else if (project.headroom) "REAL HEADROOM" else "REAL",
        .physics => arcade.NAMES[@intFromEnum(arcade.model)],
        .class => params.CLASSES[arcade.class].name,
        .shading => project.SHADES[project.shade],
        .distance => std.fmt.bufPrint(buf, "{}", .{d.play_r}) catch "",
        .music => if (d.audio.player.on) "ON" else "OFF",
        .haze => if (d.cur().mood.haze_strength == 0) "NONE" else if (!haze.on) "OFF" else if (haze.active) "ON" else "NO ROOM",
        .back => "",
    };
}

/// A row's value one step on (+1) or back (-1), wrapping.
pub fn change(d: anytype, r: Row, step: i32) void {
    switch (r) {
        .laps => rules.race_laps = rules.nextLaps(rules.race_laps, step),
        .shadow => nextShadow(d),
        .physics => setPhysics(if (arcade.model == .arcade) .classic else .arcade),
        .class => arcade.class = @intCast(@mod(@as(i32, arcade.class) + step, @as(i32, params.CLASSES.len))),
        .shading => setShade(d, @intCast(@mod(@as(i32, project.shade) + step, @as(i32, project.SHADES.len)))),
        .distance => setDistance(d, @intCast(R_MIN + @mod(@as(i32, @intCast(d.play_r)) - R_MIN + step, R_MAX - R_MIN + 1))),
        .music => d.audio.toggleMusic(),
        .haze => setHaze(d, !haze.on),
        .back => return,
    }
    var b: [8]u8 = undefined;
    zg.Console.log("racer,option,{s},{s}", .{ @tagName(r), value(d, r, &b) });
}

/// The SHADOW row: REAL <-> CHECKERBOARD, and on a track whose import kept a shadow headroom REAL -> REAL HEADROOM ->
/// CHECKERBOARD -> REAL (every committed track has none: its row is the two values it always had).
fn nextShadow(d: anytype) void {
    if (!shadow.fake and !project.headroom and project.hasHeadroom(d.cur())) return setHeadroom(true);
    if (project.headroom) setHeadroom(false);
    setShadow(!shadow.fake);
}

pub fn setHeadroom(on: bool) void {
    project.headroom = on;
    zg.Console.log("racer,headroom,{s}", .{if (on) "ON" else "OFF"});
}

/// The PHYSICS row / key T (R82 32X feel): the next race's (game.physics: the reference's drivers stay CLASSIC).
pub fn setPhysics(m: arcade.Model) void {
    arcade.model = m;
    zg.Console.log("racer,physics,{s}", .{arcade.NAMES[@intFromEnum(m)]});
}

pub fn setShadow(fake: bool) void {
    shadow.fake = fake;
    zg.Console.log("racer,shadow,{s}", .{if (shadow.fake) "DITHER" else "REAL"});
}

/// The shading (key i's FLAT / LIT / SOFT): the track's look again (the far ground follows: trackset.groundLevel).
pub fn setShade(d: anytype, s: u8) void {
    project.shade = s;
    ts.look(d);
    zg.Console.log("racer,shade,{s}", .{project.SHADES[project.shade]});
}

/// The horizon haze (M6, key q): the track's look again, with or without it.
pub fn setHaze(d: anytype, on: bool) void {
    haze.on = on;
    ts.look(d);
    zg.Console.log("racer,hazeopt,{s}", .{if (haze.on) "ON" else "OFF"});
}

/// A haze --break switch flipped: the look and the bands again.
pub fn breakHaze(d: anytype, flag: *bool) void {
    flag.* = !flag.*;
    ts.look(d);
    haze.invalidate();
}

/// The player's draw distance (keys 3-8): in force now unless a bench lap holds its own.
pub fn setDistance(d: anytype, r: u32) void {
    d.play_r = r;
    if (d.drive.mode != .bench and d.game.mode != .bench) d.r = ts.playR(d);
}
