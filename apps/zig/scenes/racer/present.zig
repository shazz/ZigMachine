// --------------------------------------------------------------------------
// RACER: what a frame shows and prints once it is drawn, split from racer.zig (file size): the HUD
// bands (the benchmark's lines, or the race's two lines and the minimap), the benchmark reporter
// and the log lines of lap v1 and the race. All of it is a function of the Demo (any struct with
// its fields), like keys.zig. The race's lines:
//
//   racer,cars,<race ticks>,<crc32 of every car's state>,<state>,<place>     every 60 frames of a race
//   racer,state,<state>,<race ticks>                                          on every FSM change
//   racer,result,<win|timeout>,<hash>,<finish ticks x8>,<order x8>            when the results show
//   racer,watch,<longest off-asphalt run x8>,<longest wall run x8>            ... and with them
//   racer,aius,<ticks>,<avg us a tick>,<max us>                               the AI half of a tick (0 headless)
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const bench = @import("bench.zig");
const cam = @import("cam.zig");
const drive = @import("drive.zig");
const fx = @import("fx.zig");
const game = @import("game.zig");
const project = @import("project.zig");
const shadow = @import("shadow.zig");
const race = @import("race.zig");
const racehud = @import("racehud.zig");
const session = @import("session.zig");
const standings = @import("standings.zig");

fn trackName(d: anytype) []const u8 {
    return d.lib.list[d.which].label();
}

pub fn mulName() []const u8 {
    return if (fx.use_f32) "F32" else if (fx.use_zmx) "MULSH" else "PLAIN";
}

pub fn knobs(d: anytype) bench.Knobs {
    return .{ .track = trackName(d), .r = d.r, .cpu = d.p.cpu_fill, .mul = mulName() };
}

fn povName(d: anytype) []const u8 {
    if (d.pose == null and d.game.mode != .off) return @tagName(d.game.pov);
    if (d.pose == null and d.drive.mode != .off) return d.drive.label();
    return @tagName(if (d.pose) |k| @as(cam.Pov, @enumFromInt(k % 3)) else cam.povAt(d.script));
}

/// Push the skidmarks and the cars (the race's eight, or driving's one) after collect and before sort.
pub fn addCars(d: anytype, v: *const cam.View) void {
    if (d.pose != null) return;
    if (d.game.mode != .off) {
        d.game.skid.draw(&d.f, &d.caches[1], v);
        d.game.drawCars(&d.f, &d.caches[0], v, d.r);
    } else if (d.drive.mode != .off) {
        d.drive.skid.draw(&d.f, &d.caches[1], v);
        d.drive.drawCar(&d.f, &d.caches[0], v);
    }
}

/// The HUD bands, the minimap, the benchmark's report and the logs of this frame.
pub fn finish(d: anytype, zigos: *zg.ZigOS, fb: *zg.LogicalFB, c: bench.Counts) void {
    var b0: [48]u8 = undefined;
    var b1: [48]u8 = undefined;
    const racing = d.game.mode != .off and d.pose == null;
    d.hud.draw(zigos, fb, d.back, .{
        .track = trackName(d), .shade = project.TAGS[project.shade], .shadow = if (shadow.fake) "/DITHER" else "", .r = d.r, .cpu = d.p.cpu_fill, .mul = mulName(), .decals = d.decals,
        .pov = povName(d), .polys = c.polys, .spans = c.spans, .osd = d.osd,
        .uncapped = d.uncapped, .avg_us = d.bench.avg_us, .fps10 = d.bench.fps10, .stage_us = d.bench.stage_us,
        .line0 = if (racing) racehud.top(&b0, &d.game) else null,
        .line1 = if (racing) racehud.bottom(&b1, &d.game) else null,
    });
    if (racing) drawMap(d, fb);
    d.bench.lap(.hud);
    const closed = d.bench.frameEnd();
    const driven = d.drive.mode != .off and d.pose == null;
    const lap_frames: u32 = if (racing) game.ROUND_FRAMES else cam.LAP_FRAMES;
    const script = if (racing) d.game.frames else if (driven) d.drive.frames else d.script;
    const scripted = d.pose == null and !d.paused and (if (racing) d.game.mode == .bench else d.drive.mode != .drive);
    d.rep.report(zigos, fb, &d.bench, knobs(d), c, .{ .script = script, .scripted = scripted, .lap_frames = lap_frames });
    if (driven) logPhysics(d);
    if (racing) raceLog(d);
    if (closed) d.bench.resetWindow();
}

fn drawMap(d: anytype, fb: *zg.LogicalFB) void {
    var pos: [race.NCARS][3]i32 = undefined;
    for (&pos, 0..) |*p, k| p.* = d.game.shown(k).pos;
    d.map.draw(fb.fb[0 .. fb.stride * 200], fb.stride, &pos);
}

/// Lap v1: the physics state every 60 frames and the tick cost at the lap's end (the board / browser / reference compare these).
fn logPhysics(d: anytype) void {
    var buf: [160]u8 = undefined;
    if (d.drive.frames % bench.CRC_EVERY != 0) return;
    zg.Console.log("{s}", .{d.drive.stateLine(&buf)});
    if (d.drive.frames % cam.LAP_FRAMES == 0) zg.Console.log("{s}", .{drive.perfLine(&d.drive, &buf)});
}

fn raceLog(d: anytype) void {
    const g = &d.game;
    const st = g.s.fsm.state;
    if (st != g.logged) {
        zg.Console.log("racer,state,{s},{}", .{ @tagName(st), g.s.race.ticks });
        if (st == .results) logResult(g);
        g.logged = st;
    }
    if (g.frames % bench.CRC_EVERY == 0 and st != .grid) {
        zg.Console.log("racer,cars,{},{x:0>8},{s},{}", .{ g.s.race.ticks, g.s.race.crc(), @tagName(st), g.s.playerPlace() });
    }
    if (g.mode == .bench and g.frames % game.ROUND_FRAMES == 0) {
        const r = &g.s.race;
        zg.Console.log("racer,aius,{},{},{}", .{ r.ticks, if (r.ticks == 0) 0 else r.ai_us / r.ticks, r.ai_max });
    }
}

fn logResult(g: *const game.Game) void {
    const s = &g.s;
    const u = s.us();
    var ord: [standings.MAXCARS]u8 = undefined;
    const o = standings.order(&u, &s.finish, s.race.n, &ord);
    var b: [4][96]u8 = undefined;
    zg.Console.log("racer,result,{s},{x:0>8},{s},{s}", .{ @tagName(s.outcome), s.resultHash(), csv(u32, &b[0], &s.finish), csv(u8, &b[1], o) });
    zg.Console.log("racer,watch,{s},{s}", .{ csv(u32, &b[2], &s.watch.off_max), csv(u32, &b[3], &s.watch.wall_max) });
}

/// `xs` as "a,b,c" (no spaces: the harness splits the line on commas).
fn csv(comptime T: type, buf: []u8, xs: []const T) []const u8 {
    var n: usize = 0;
    for (xs, 0..) |x, i| n += (std.fmt.bufPrint(buf[n..], "{s}{}", .{ if (i == 0) "" else ",", x }) catch return buf[0..n]).len;
    return buf[0..n];
}
