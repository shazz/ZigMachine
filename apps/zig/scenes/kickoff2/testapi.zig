// --------------------------------------------------------------------------
// The headless harness's door into the match (apps/kickoff2_headless.mjs):
// start the curated England v Spain friendly exactly as the scene does, run
// 50 Hz ticks with a scripted key mask, and read back scores, phase, clock,
// the ball and the whole match state for CRCs. It drives the SAME MatchP the
// scene plays. Pulled in only when this scene IS the cart (kickoff2.zig
// checks cart.Cart), so the exports never leak into another cart.
// --------------------------------------------------------------------------
const g = @import("gs.zig");
const players = @import("players.zig");
const scene = @import("../kickoff2.zig");

/// human key mask (test-side layout): bit0 up, 1 down, 2 left, 3 right
/// (diagonals composed as the scene's maskDir does), 4 fire held.
export fn ko2TestStart(seed: u32) void {
    players.init(&scene.match);
    scene.match.rng.state[0] = @truncate(seed);
    scene.match.rng.state[1] = @truncate(seed >> 8);
    scene.match.rng.state[2] = @truncate(seed >> 16);
}

fn maskDir(m: u32) u8 {
    const u = m & 1 != 0;
    const d = m & 2 != 0;
    const l = m & 4 != 0;
    const r = m & 8 != 0;
    if (u and r) return 1;
    if (r and !u and !d) return 2;
    if (d and r) return 3;
    if (d) return 4;
    if (d and l) return 5;
    if (l) return 6;
    if (u and l) return 7;
    if (u) return 0;
    return 8;
}

/// One 50 Hz match tick (the scene's tick50, minus its own input latching —
/// the harness's rising-edge fire is expressed by the mask itself).
export fn ko2TestTick(mask: u32) u32 {
    const c = g.Control{ .dir = maskDir(mask), .fire = mask & 16 != 0, .fireRising = mask & 32 != 0 };
    players.tick(&scene.match, c, .{});
    return matchPhase();
}

fn matchPhase() u32 {
    return switch (scene.match.phase) {
        .front => 0,
        .kickoff_wait => 1,
        .playing => 2,
        .goal_pause => 3,
        .half_time => 4,
        .full_time => 5,
    };
}

export fn ko2Phase() u32 {
    return matchPhase();
}
export fn ko2Half() u32 {
    return scene.match.half;
}
export fn ko2Score(t: u32) u32 {
    return if (t == 0) scene.match.teams[0].score else scene.match.teams[1].score;
}
export fn ko2Clock() u32 {
    return scene.match.clock;
}
/// A player's fixed position, so the harness can measure the runner's real
/// speed in units/tick instead of settling for "it moved". The pace word is
/// 216000 in 16.16 = 3.30 units/tick = 165 units/s, and the man the human
/// steers runs it +20 = 180 units/s (original_controls.go:685 sets the step).
export fn ko2TestPosX(team: u32, idx: u32) i32 {
    return scene.match.teams[team & 1].players[idx % g.squad_size].pos[0];
}
export fn ko2TestPosY(team: u32, idx: u32) i32 {
    return scene.match.teams[team & 1].players[idx % g.squad_size].pos[1];
}
/// Which outfielder team 0's human currently controls (the harness's runner).
export fn ko2TestControlled() u32 {
    return scene.match.teams[0].controlled;
}
export fn ko2BallPos(ptr: u32) void {
    if (ptr != 0) {
        const p: *[2]i32 = @ptrFromInt(ptr);
        p.* = scene.match.ball.pos;
    }
}
/// Test hook: drop the ball just outside an end line, off the goal mouth so it
/// is an end out and not a goal, with `lastTeam` as the last touch. The harness
/// uses it to check who takes the restart that follows — a goal kick is the
/// GOALKEEPER's (restarts.go:24 forces Player = 0 for GoalKick), a corner the
/// attacking team's.
export fn ko2TestForceEndOut(lastTeam: u32, bottom: u32) void {
    const m = &scene.match;
    m.gf.outKind = 0;
    m.gf.outX = 0;
    m.gf.outY = 0;
    m.ball.pos = .{ g.fx(600), if (bottom != 0) g.fx(1420) else g.fx(-28) };
    m.ball.vel = .{ 0, 0 };
    m.ball.height = 0;
    m.ball.lift = 0;
    m.ball.curve = 0;
    m.ball.lastTeam = @intCast(lastTeam);
    m.ball.lastPlayer = 0;
    m.ball.trappedBy = -1;
    m.ballVisible = true;
}
export fn ko2TestRestartKind() u32 {
    return switch (scene.match.restart.kind) {
        .kickoff => 0,
        .goal_kick => 1,
        .corner => 2,
        .throw_in => 3,
        .after_goal => 4,
    };
}
export fn ko2TestRestartTeam() u32 {
    return scene.match.restart.team;
}
export fn ko2TestRestartTaker() u32 {
    return scene.match.restart.taker;
}
/// Test hook: the half-time transition the scene performs at the half_time
/// phase (kickoff2.zig:118-128) — swap ends, restart the clock and hand the
/// kickoff to team 1 — so the harness can check the mirrored second half
/// without sitting through a period.
export fn ko2TestSecondHalf() void {
    scene.match.half = 1;
    scene.match.clock = 0;
    scene.match.teams[0].attackDown = !scene.match.teams[0].attackDown;
    scene.match.teams[1].attackDown = !scene.match.teams[1].attackDown;
    players.kickoff(&scene.match, 1);
}
/// Test hook: park the ball at an in-play spot (whole units), so a probe can
/// pull the camera to an end before forcing a restart there (the camera moves
/// at 2 units/tick, so it needs seconds to travel the pitch).
export fn ko2TestPlaceBall(x: u32, y: u32) void {
    const m = &scene.match;
    m.gf.outKind = 0;
    m.ball.pos = .{ g.fx(@intCast(x)), g.fx(@intCast(y)) };
    m.ball.vel = .{ 0, 0 };
    m.ball.height = 0;
    m.ball.lift = 0;
    m.ball.trappedBy = -1;
}
/// Test hook: put the ball inside a goal mouth for one tick, so the harness can
/// check which team the goal is credited to. outKind 3 is the top mouth
/// (y < 0), 4 the bottom; the scorer is the team attacking that end.
export fn ko2TestForceGoal(bottom: u32) void {
    const m = &scene.match;
    m.gf.outKind = 0;
    m.gf.contactCooldown = 0;
    m.ball.pos = .{ g.fx(456), if (bottom != 0) g.fx(1420) else g.fx(-20) };
    m.ball.vel = .{ 0, 0 };
    m.ball.height = 0;
    m.ball.lift = 0;
    m.ball.curve = 0;
    m.ball.lastTeam = 0;
    m.ball.lastPlayer = 0;
    m.ball.trappedBy = -1;
    m.ballVisible = true;
}
export fn ko2RamPtr() [*]u8 {
    return @ptrCast(&scene.match);
}
export fn ko2RamLen() u32 {
    return @sizeOf(players.MatchP);
}
/// The Campbell plane's char buffer (64000 bytes: the 320x200 shown fb).
export fn ko2ScreenPtr() [*]u8 {
    return scene.screenFB;
}
