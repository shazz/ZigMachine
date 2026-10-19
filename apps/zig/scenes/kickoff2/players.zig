// --------------------------------------------------------------------------
// Kickoff2 — players, control and the match flow. Transcribed from the Go
// remake's engine: original_controls.go (human + camera targets + pace),
// original_pass.go (possession/AI chain), original_keeper*.go, restarts.go,
// and players.go (per-tick actor pass).
//
// Curated-port simplifications (each marked SIMPLIFIED): fouls/officials and
// penalties are out of scope; corners keep the directional panel but auto-aim;
// the ball_direction 16-sector heading hysteresis is kept, the jump-header is
// kept for the CPU, and the "scissor" is dropped (dive-in free kicks too).
// --------------------------------------------------------------------------
const std = @import("std");
const g = @import("gs.zig");
const ballMod = @import("ball.zig");
const sfx = @import("sfx.zig");

pub const Team = struct {
    players: [g.squad_size]g.Player = [_]g.Player{.{}} ** g.squad_size,
    score: u8 = 0,
    attackDown: bool = true, // attacks toward y = PitchHeight
    controlled: u5 = 9, // the human's current outfield player index
    human: bool = false,
    name: []const u8 = "",
};

pub const MatchP = struct {
    teams: [2]Team = .{ .{ .human = true, .name = "ENGLAND" }, .{ .human = false, .name = "SPAIN" } },
    ball: g.Ball = .{},
    gf: g.GoalFrame = .{},
    ballPrev: [2]i32 = .{ 0, 0 },
    ballVisible: bool = true,
    rng: g.Rng = .{},
    clock: u32 = 0, // 50 Hz ticks of play this half
    phase: g.Phases = .kickoff_wait,
    restart: g.Restart = .{},
    half: u1 = 0,
    scorer: i8 = -1, // last shooter (celebration focus + credit)
    pauseTimer: u32 = 0,
    aftertouch: struct { lateral: i32 = 0, vertical: i32 = 0, ticks: u32 = 0 } = .{},
};

pub fn init(m: *MatchP) void {
    m.* = .{};
    m.teams[0].players[0].keeper = true;
    m.teams[1].players[0].keeper = true;
    for (0..2) |t| {
        const team = &m.teams[t];
        team.attackDown = (t == 0); // first half: team 0 attacks down (y+)
        for (0..g.squad_size) |i| {
            const p = &team.players[i];
            p.keeper = (i == 0);
            // Original pace byte: round(Pace*200) with Pace 0.72 -> 144;
            // originalPace(p) = 180 + (144>>2) = 216 (in per-step 16.16/1000).
            const paceWord: i32 = if (p.keeper) 190 else 216;
            p.pace = paceWord * 1000; // units^16.16/step
            p.paceFixed = paceWord * 1000;
            p.facing = if (team.attackDown) 4 else 0;
            p.state = 1;
        }
    }
    kickoff(m, 0);
}

// --------------------------------------------------------------------------
// Kickoff / restarts (restarts.go beginRestart / takeRestart, simplified).
// --------------------------------------------------------------------------

/// Positions the players for a (re)start and freezes play on the ball.
pub fn kickoff(m: *MatchP, team: u1) void {
    m.restart = .{ .active = true, .kind = .kickoff, .team = team, .taker = 9, .pos = .{ g.fx(456), g.fx(696) }, .countdown = 100 };
    resetPositions(m);
    m.ball = .{ .pos = .{ g.fx(456), g.fx(696) } };
    m.ballVisible = true;
    m.aftertouch = .{};
    m.phase = .kickoff_wait;
    sfx.requestWhistle();
}

/// Set up a dead-ball restart: the ball is placed, every outfielder walks to
/// its RestartTacticPosition target (kickoff 12/13, goal-kick 14/15, corner
/// 16..19 — all tactic-file targets verbatim), and the taker lines up behind.
pub fn beginRestart(m: *MatchP, kind: g.RestartKind, team: u1, pos: [2]i32) void {
    m.restart = .{ .active = true, .kind = kind, .team = team, .pos = pos, .countdown = 80, .choice = 4 };
    // The taker: the outfielder nearest the ball, then the target-side wander.
    // Goal kicks are the exception — the keeper takes them (restarts.go:24-28
    // forces Restart.Player = 0 for GoalKick, which is why only an outfielder
    // ever appeared to kick one while the keeper stood on the ball).
    var bt: u5 = 1;
    if (kind == .goal_kick) {
        bt = 0;
    } else {
        var bd: i32 = 1 << 30;
        for (1..g.squad_size) |i| {
            const d2 = distI2(team0pos(m, team, @intCast(i)).*, pos);
            if (d2 < bd) { bd = d2; bt = @intCast(i); }
        }
    }
    m.restart.taker = bt;
    m.phase = .kickoff_wait;
    m.ball.pos = pos;
    m.ball.vel = .{ 0, 0 };
    m.ball.height = 0;
    m.ball.lift = 0;
    m.ball.trappedBy = -1;
    m.ballVisible = true;
    m.aftertouch = .{};
    resetPositions(m);
}

pub fn resetPositions(m: *MatchP) void {
    const ball = m.ball.pos;
    for (0..2) |t| {
        const team = &m.teams[t];
        for (1..g.squad_size) |i| {
            const p = &team.players[i];
            const take = (t == m.restart.team and i == m.restart.taker);
            const slot = g.tacticPos(@intCast(t), @intCast(i), g.unfix(ball[0]), g.unfix(ball[1]), team.attackDown);
            p.pos = .{ g.fx(slot[0]), g.fx(slot[1]) };
            p.step = 0;
            p.state = 1;
            p.target = .{ g.fx(slot[0]), g.fx(slot[1]) };
            p.dirHistory = 0;
            if (m.restart.active and take) {
                // The taker stands 17 units behind the ball, facing upfield.
                const dir = upfield(team.attackDown);
                const v = g.dirVec(dir);
                p.pos = .{ ball[0] - v[0] * 17, ball[1] - v[1] * 17 };
                p.facing = dir;
                p.state = 1;
            }
        }
        const k = &team.players[0];
        if (t == m.restart.team and m.restart.kind == .goal_kick) {
            // The GOALKEEPER takes the goal kick: restarts.go:24-32 forces
            // Restart.Player = 0 for GoalKick and picks the nearest outfielder
            // for every other kind. He waits behind the ball facing upfield,
            // then boots it (takeRestart below).
            const dir = upfield(team.attackDown);
            const v = g.dirVec(dir);
            k.pos = .{ ball[0] - v[0] * 17, ball[1] - v[1] * 17 };
            k.facing = dir;
        } else {
            // Own goal line: a team defends the end it does NOT attack.
            k.pos = .{ g.fx(456), g.fx(if (team.attackDown) 6 else 1386) };
            k.facing = upfield(team.attackDown);
        }
        k.step = 0;
        k.state = 1;
    }
}

/// The direction a team attacks in: `attackDown` is the Go's
/// AttackDirection(team) > 0 (match.go:246-258) — team 0 attacks toward +y in
/// the first half — so everything that picks an end (the keeper's own goal
/// line, restart facing, clearances) reads the direction from here. The
/// keeper/restart/score code used to be written the other way round (keeper on
/// the line the team was attacking, kicks aimed at its own goal).
fn upfield(attackDown: bool) u3 {
    return if (attackDown) 4 else 0; // S (+y) / N (-y)
}

/// The restart launch (restarts.go takeRestart): kind-specific power/lift.
fn takeRestart(m: *MatchP, charge: i32) void {
    const r = &m.restart;
    const team = &m.teams[r.team];
    const opp: u1 = if (r.team == 0) 1 else 0;
    const taker = &team.players[r.taker];
    const dir = upfield(team.attackDown);
    _ = opp;
    switch (r.kind) {
        .throw_in => {
            // ThrowIn: 220/75 forward, 330/110 back-to-attack; ±40% inward.
            const v = g.dirVec(g.dirIndex(g.fx(456) - m.ball.pos[0], g.fx(696) - m.ball.pos[1]));
            m.ball.vel[0] = v[0] * 7; // 220 kicks / 30-step OP_TABLE row -> 7 units/step
            m.ball.vel[1] = v[1] * 7;
            m.ball.lift = 50 * 1000;
            m.ball.trappedBy = -1;
        },
        .goal_kick => {
            const v = g.dirVec(dir);
            const w: u32 = m.rng.word();
            _ = w;
            m.ball.vel[0] = v[0] * 6; // 410 kicks / ~65 -> 6 units/step
            m.ball.vel[1] = v[1] * 6;
            m.ball.lift = 120 * 1000;
            m.ball.trappedBy = -1;
        },
        .corner => {
            // OriginalCornerState (original_physics.go:142-167): the vertical
            // + curve tables keyed by the panel choice; base velX ±500000.
            const c = @as(usize, r.choice);
            const verts = [9]i32{ 100000, 50000, 50000, 100000, 150000, 150000, 150000, 100000, 50000 };
            const curves = [9]i32{ 0, 0, -4500, -4500, -4500, 0, 4500, 4500, 4500 };
            const vert = verts[c];
            const curve = curves[c];
            const sgn: i32 = if (r.pos[0] < g.fx(456)) 1 else -1; // X sign by half-plane
            const ysgn: i32 = if (r.pos[1] < g.fx(696)) 1 else -1;
            m.ball.vel[0] = sgn * 500000;
            m.ball.vel[1] = ysgn * g.FSCALE;
            m.ball.lift = vert;
            m.ball.curve = curve;
            // The charge scales the power: min(charge,20)+4 → 5..24 /25.
            const mult = @divTrunc(1000 * (@min(charge, 20) + 4), 25);
            m.ball.vel[0] = @divTrunc(m.ball.vel[0] * mult, 1000);
            m.ball.vel[1] = @divTrunc(m.ball.vel[1] * mult, 1000);
            m.ball.trappedBy = -1;
        },
        .kickoff => {
            // KickOff 300/8 via the pass target table (players.go 377-403).
            const recv = passTarget(m, r.team, r.taker);
            if (recv == 255) {
                const v = g.dirVec(dir);
                m.ball.vel[0] = v[0] * 4;
                m.ball.vel[1] = v[1] * 4;
                m.ball.trappedBy = -1;
            } else {
                const target = m.teams[r.team].players[recv].pos;
                ballMod.passLaunch(&m.ball, target, taker, 80, &m.rng);
                m.teams[r.team].players[recv].ownerTicks = 100;
            }
        },
        .after_goal => {},
    }
    m.restart.active = false;
    m.phase = .playing;
    m.ball.lastTeam = @intCast(r.team);
    m.ball.lastPlayer = @intCast(r.taker);
    sfx.requestKick();
}

/// Pick the receiver for a kickoff/gk pass (players.go passTarget, trimmed to
/// KO2 host behaviour: toward goal + longest distance, opponent clear).
fn passTarget(m: *MatchP, team: u1, from: u5) u8 {
    const teamRef = &m.teams[team];
    var best: u8 = 255;
    var bestScore: i32 = -1 << 30;
    const opp: u1 = if (team == 0) 1 else 0;
    for (1..g.squad_size) |i| {
        if (i == from) continue;
        const p = &teamRef.players[i];
        // Whole units, not 16.16: shift the deltas before squaring, like
        // dist2Ball/distI2/distI. Shifting the sum instead squares a 16.16
        // delta first (a 700-unit dx is 2.1e15) which wraps i32, and the >>16
        // then leaves dist2 at 65536x the unit the 35..350 window below is
        // written in -- so the loop matched nothing and kickoff/GK passes
        // picked no receiver at all.
        const dx = (p.pos[0] - teamRef.players[from].pos[0]) >> 16;
        const dy = (p.pos[1] - teamRef.players[from].pos[1]) >> 16;
        const dist2 = dx * dx + dy * dy;
        const progress: i32 = if (teamRef.attackDown) dy else -dy;
        if (dist2 < 35 * 35 or dist2 > 350 * 350) continue;
        var score = @divTrunc(dist2, 100) + progress - @divTrunc(@divTrunc(25 * dist2, 100), 100);
        if (nearestOppDist2(m, opp, p.pos) < 55 * 55) score -= 75;
        if (score > bestScore) {
            bestScore = score;
            best = @intCast(i);
        }
    }
    return best;
}

fn nearestOppDist2(m: *MatchP, team: u1, target: [2]i32) i32 {
    var best: i32 = 1 << 30;
    for (1..g.squad_size) |i| {
        const p = &m.teams[team].players[i];
        const dx = (p.pos[0] - target[0]) >> 16;
        const dy = (p.pos[1] - target[1]) >> 16;
        const d2 = dx * dx + dy * dy;
        if (d2 < best) best = d2;
    }
    return best;
}

// --------------------------------------------------------------------------
// The tick.
// --------------------------------------------------------------------------
pub fn tick(m: *MatchP, human: g.Control, cpu: g.Control) void {
    switch (m.phase) {
        .front, .full_time => return,
        .kickoff_wait => {
            m.restart.countdown -= 1;
            if (m.restart.countdown <= 0) {
                m.restart.active = false;
                m.phase = .playing;
                takeRestart(m, 0);
            }
        },
        .goal_pause => {
            m.pauseTimer -= 1;
            if (m.pauseTimer <= 0) {
                const conceded: u1 = if (lastGoalTeam == 0) 1 else 0;
                kickoff(m, conceded);
            }
        },
        .half_time, .playing => {},
    }

    if (m.phase == .playing) {
        stepPlaying(m, human, cpu);
        // a goal (or dead ball) inside stepPlaying stops the half clock in
        // the very tick it happens — the scoreboard freezes at the whistle
        if (m.phase != .playing) return;
        m.clock += 1;
        if (m.clock >= g.half_limit) {
            if (m.half == 0) {
                m.phase = .half_time;
                sfx.requestWhistle();
            } else {
                m.phase = .full_time;
                sfx.requestFullTime();
            }
        }
    } else if (m.phase == .kickoff_wait) {
        // camera drift on the restart target
    }
}

var lastGoalTeam: u1 = 0;

fn stepPlaying(m: *MatchP, human: g.Control, cpu: g.Control) void {
    const ev = sfx.reqEvent();
    // 1. Ball integration BEFORE players (the source's 1-tick touch lag).
    var gflessSound = false;
    m.ballPrev = m.ball.pos;
    ballMod.step(&m.ball, &m.gf, 0, 0, ev);
    gflessSound = ballMod.goalFrameStep(&m.ball, &m.gf, m.ballPrev[1], ev);
    if (gflessSound) sfx.requestPost();

    m.ballVisible = !(m.ball.trappedBy != -1 and (carrierPose(m)));
    if (m.ballVisible and m.ball.height < 0) m.ball.height = 0;

    // 2. Boundary: side out -> throw-in; end out -> corner / goal kick.
    switch (m.gf.outKind) {
        1 => {
            // Throw-in: the opposite of the last toucher's team; the ball is
            // placed ON the touchline (original_throwin.go's crossing point).
            const lastTeam: u1 = if (m.ball.lastTeam <= 0) 1 else 0;
            const oy: i32 = g.clampI(@as(i32, m.gf.outY), 16, 1376);
            beginRestart(m, .throw_in, lastTeam, .{ g.fx(clampSide(@as(i32, m.gf.outX))), g.fx(oy) });
            m.gf.outKind = 0;
            return;
        },
        2 => {
            // End out at `myGoal`'s end (0 = the top line, 1 = the bottom).
            // A goal kick belongs to the team defending that end (and its
            // keeper takes it); a corner to the team attacking it.
            const myGoal: u1 = if (m.gf.outY < 696) 0 else 1;
            const attacker = attackTeamOfEnd(m, myGoal == 0);
            const cx: i32 = if (m.gf.outX < 456) 8 else 904;
            const cy: i32 = if (myGoal == 0) 8 else 1384;
            if (m.ball.lastTeam == attacker) {
                // Attacker last touched: goal kick for the defender, 66 units
                // in front of the line — original_goal_kick.go walks the keeper
                // to (348|564, 12|1380) and then drops the ball at
                // (target.X, 66|1326) for the run-up.
                beginRestart(m, .goal_kick, otherU1(attacker), .{
                    g.fx(if (m.gf.outX < 456) 348 else 564),
                    g.fx(if (myGoal == 0) 66 else 1326),
                });
            } else {
                beginRestart(m, .corner, attacker, .{ g.fx(cx), g.fx(cy) });
            }
            m.gf.outKind = 0;
            return;
        },
        3, 4 => {
            // GOAL: outKind 3 is the top goal mouth (y < 0), 4 the bottom. The
            // scorer is the team attacking that end — which follows attackDown,
            // so it is already right after the half-time swap.
            const scorerTeam: u1 = attackTeamOfEnd(m, m.gf.outKind == 3);
            goalScored(m, scorerTeam);
            m.gf.outKind = 0;
            return;
        },
        else => {},
    }

    // 2.7. The human's automatic control hand-over (0xc7d4's 24-unit gate).
    if (m.teams[0].human) autoSwitch(m, human);

    // 3. Players pass (field + keeper each team), then collisions.
    for (0..2) |t| {
        const team = &m.teams[t];
        for (0..g.squad_size) |i| {
            const p = &team.players[i];
            if (p.keeper) {
                stepKeeper(m, @intCast(t), p);
            } else if (team.human and i == team.controlled) {
                stepHumanField(m, @intCast(t), @intCast(i), human);
            } else {
                stepAIField(m, @intCast(t), @intCast(i), cpu);
            }
            stepDecay(p);
        }
    }
    // 4. Human aftertouch (state 44, shot actor) if human's shot is live.
    updateHumanAftertouch(m, human);
}

fn team0pos(m: *MatchP, t: u1, i: u5) *[2]i32 {
    return &m.teams[t].players[i].pos;
}

fn otherU1(t: u1) u1 {
    return if (t == 0) 1 else 0;
}

fn clampSide(x: i32) i32 {
    // on the touchline, inside or on it
    return g.clampI(x, 0, g.PitchWidth);
}

/// The team that ATTACKS the end `topGoal` names: team 0 attacks toward +y
/// (the bottom line) in the first half, so the top line is the other team's to
/// attack. This is what the function used to compute, under a name and a call
/// site that read it as the DEFENDER — which sent every goal kick to the
/// attacker and credited every goal to the team that conceded it.
fn attackTeamOfEnd(m: *MatchP, topGoal: bool) u1 {
    const team0AttacksDown = m.teams[0].attackDown;
    if (team0AttacksDown) return if (topGoal) 1 else 0;
    return if (topGoal) 0 else 1;
}

/// True when the ball is glued to a carrying keeper (the original hides the
/// independent ball sprite: the keeper sprite carries it).
fn carrierPose(m: *MatchP) bool {
    if (m.ball.trappedBy < 0) return false;
    const t: u1 = @intCast(@divTrunc(m.ball.trappedBy, 11));
    const p: u5 = @intCast(@mod(m.ball.trappedBy, 11));
    return m.teams[t].players[p].keeper;
}

pub fn goalScored(m: *MatchP, team: u1) void {
    m.teams[team].score += 1;
    m.phase = .goal_pause;
    m.pauseTimer = 350;
    lastGoalTeam = team;
    m.scorer = m.ball.lastPlayer;
    sfx.requestGoal();
}

pub fn camTarget(m: *MatchP) [2]i32 {
    return m.ball.pos;
}

// ==========================================================================
// The per-actor steps.
// ==========================================================================

/// Per-actor decay (players.go stepDecay tail).
pub fn stepDecay(p: *g.Player) void {
    if (p.actionTicks > 0) p.actionTicks -= 1;
    if (p.touchCooldown > 0) p.touchCooldown -= 1;
    if (p.jumpTicks > 0) {
        p.jumpTicks -= 1;
        if (p.jumpTicks == 0 and p.state == 13) p.state = 1;
    }
    p.spriteIndexOverride = null;
}

/// The distance-driven phase accumulator (original_controls advanceOriginalAnimation).
fn advanceAnim(p: *g.Player) void {
    if (p.step == 0) return; // stationary runners keep their phase
    const add: u16 = @intCast(@min(@divTrunc(@divTrunc(p.step, 1000), 1) * 2, 8));
    p.animPhase +%= add;
    if (p.animPhase >> 8 >= 38) p.animPhase -= 0x2600;
}

fn dist2Ball(p: *const g.Player, m: *MatchP) i32 {
    const dx = (p.pos[0] - m.ball.pos[0]) >> 16;
    const dy = (p.pos[1] - m.ball.pos[1]) >> 16;
    return dx * dx + dy * dy;
}

fn setFacingTo(p: *g.Player, target: [2]i32) void {
    const dx = target[0] - p.pos[0];
    const dy = target[1] - p.pos[1];
    p.facing = g.dirIndex(dx, dy);
}

fn moveBy(p: *g.Player, dir: u3, step: i32) void {
    const v = g.dirVec(dir);
    p.step = step;
    p.facing = dir;
    // 16.16 direction x 16.16 step -> 16.16 distance. The product MUST be taken
    // wide: a unit vector (65536) times a pace word (216000) is 1.4e10, which
    // wraps i32 (players crawl at ~0.3 units/tick instead of 3.30) or panics in
    // a safe build. The Go takes it in float64 (original_controls.go:685,
    // Step*1000*TPS/65536 = 3.30 units/tick), so i64 is the same arithmetic.
    const dx = @divTrunc(@as(i64, v[0]) * step, g.FSCALE);
    const dy = @divTrunc(@as(i64, v[1]) * step, g.FSCALE);
    p.pos[0] += @as(i32, @intCast(dx));
    p.pos[1] += @as(i32, @intCast(dy));
    // human clamp (originalHumanRun 40..952 / -40..1432)
    p.pos[0] = g.clampI(p.pos[0], g.fx(40), g.fx(952));
    p.pos[1] = g.clampI(p.pos[1], g.fx(-40), g.fx(1432));
}

// --------------------------------------------------------------------------
// HUMAN outfield player (original_controls.go updateOriginalHuman).
// --------------------------------------------------------------------------
/// The original's control hand-over (0xc7d4): keep the current man unless he
/// has fallen at least 24 units off the ball and a teammate is meaningfully
/// closer (16 units more) — never yanking during an action or a fire press.
fn autoSwitch(m: *MatchP, human: g.Control) void {
    const team = &m.teams[0];
    if (m.ball.trappedBy >= 0 and @as(u1, @intCast(@divTrunc(m.ball.trappedBy, 11))) == 0) return; // we hold the ball
    const ctrl = team.controlled;
    const cur = &team.players[ctrl];
    if (cur.state == 11 or cur.state == 13 or cur.state == 30 or cur.actionTicks > 0) return;
    const dCur = dist2Ball(cur, m);
    if (dCur <= 576 or human.fire) return; // the 24-unit gate
    var best: u5 = ctrl;
    var bd: i32 = dCur;
    for (0..g.squad_size) |i| {
        if (i == ctrl or team.players[i].keeper) continue;
        const d = dist2Ball(&team.players[i], m);
        if (d < bd) {
            bd = d;
            best = @intCast(i);
        }
    }
    if (best != ctrl and bd + 256 < dCur) {
        team.controlled = best;
        team.players[best].ownerTicks = 0;
    }
}

fn stepHumanField(m: *MatchP, t: u1, idx: u5, c: g.Control) void {
    const p = &m.teams[t].players[idx];
    advanceAnim(p);
    const near = dist2Ball(p, m) <= 64 and m.ball.height <= g.fx(12);
    const fireRising = c.fireRising;
    // The source's free-running bonus: originalHumanRun (original_controls.go:1025)
    // returns pace+20 for the man the human steers, while the ordinary NPC runner
    // keeps the plain pace (original_controls.go:1120). 236 vs 216 = 180 vs 165
    // units/s at 50 Hz. The touch/dribble keeps the plain pace (the Go's
    // OriginalDribbleState is documented as the pace word "without the human's
    // free-running +20 bonus").
    const runPace = p.pace + 20 * 1000;

    if (p.state == 13) return; // airborne (jump) handles nothing else

    if (m.ball.trappedBy >= 0 and m.ball.trappedBy == @as(i16, @intCast(@as(u16, t) * 11 + idx))) {
        // I HOLD the ball: aiming mode.
        p.state = 11;
        const tvf = g.dirVec(p.facing);
        m.ball.pos = .{ p.pos[0] + tvf[0] * 8, p.pos[1] + tvf[1] * 8 };
        m.ball.vel = .{ 0, 0 };
        if (c.dir != 8) p.facing = @truncate(c.dir);
        if (!c.fire) { // released: pass if someone's there, else shoot
            takeTrapKick(m, t, idx);
        }
        return;
    }

    if (!near) {
        // No ball interaction; the movement/jump/tackle entry points only.
        if (c.dir != 8) moveBy(p, @truncate(c.dir), runPace);
        if (fireRising and m.ball.height > g.fx(16) and dist2Ball(p, m) <= 400) {
            // jump header (state 13, 44 ticks)
            p.state = 13;
            p.jumpTicks = 44;
            p.actionTicks = 44;
        }
        return;
    }

    if (m.ball.trappedBy >= 0) {
        const tt: u1 = @intCast(@divTrunc(m.ball.trappedBy, 11));
        if (tt != t) {
            // contestable? no: the holder keeps it until we tackle (below).
            if (c.dir != 8) moveBy(p, @truncate(c.dir), runPace);
            if (fireRising) attemptTackle(m, t, idx);
            return;
        }
    }

    // Near and free: the standing trap / moving nudge.
    if (c.dir != 8) {
        moveBy(p, @truncate(c.dir), runPace);
        if (p.touchCooldown == 0 and m.ball.trappedBy < 0) {
            ballMod.dribbleLaunch(&m.ball, @truncate(c.dir), p.pace);
            m.ball.lastTeam = @intCast(t);
            m.ball.lastPlayer = @intCast(idx);
            p.touchCooldown = 15;
            p.ownerTicks = 300;
            sfx.requestKick();
        }
    } else {
        // Standing: trap fires only when the ball touches our feet.
        if (m.ball.trappedBy < 0 and dist2Ball(p, m) <= 64) {
            m.ball.trappedBy = @intCast(@as(u16, t) * 11 + idx);
            m.ball.vel = .{ 0, 0 };
            m.ball.height = 0;
            p.state = 11;
            p.ownerTicks = 300;
        }
        if (fireRising and m.ball.trappedBy < 0 and m.ball.lastTeam == @as(i8, @intCast(t))) {
            p.state = 30; // the shot actor about to launch
            p.actionTicks = 12;
        }
    }

    // A second fire press during the touch cooldown chips the ball up.
    if (fireRising and p.touchCooldown > 5) {
        ballMod.dribbleLaunch(&m.ball, @truncate(c.dir), p.pace + 30000);
        m.ball.lift = 180000;
        m.ball.lastTeam = @intCast(t);
        m.ball.lastPlayer = @intCast(idx);
    }
}

/// Release of the trap: pass if a teammate is in the facing lane, else shoot
/// (updateOriginalHuman's trap release: originalTrapPassTarget / shot).
fn takeTrapKick(m: *MatchP, t: u1, idx: u5) void {
    const p = &m.teams[t].players[idx];
    const spanDir = dirCandidate(m, t, idx);
    _ = spanDir;
    const target = trapPassTarget(m, t, idx);
    if (target.i < g.squad_size) {
        ballMod.passLaunch(&m.ball, m.teams[t].players[target.i].pos, p, 80, &m.rng);
        m.teams[t].players[target.i].ownerTicks = 100;
        sfx.requestKick();
    } else {
        shotLaunchAt(m, t, idx, p.facing);
    }
    p.state = 30;
    p.actionTicks = 16;
}

const TargetPick = struct { i: u8 = 255, dist: i32 = 1 << 30 };

/// originalTrapPassTarget: teammates within ±1 sector of the facing lane.
fn trapPassTarget(m: *MatchP, t: u1, idx: u5) TargetPick {
    var best = TargetPick{};
    const p = &m.teams[t].players[idx];
    const opp: u1 = if (t == 0) 1 else 0;
    for (1..g.squad_size) |i| {
        if (i == idx) continue;
        const q = &m.teams[t].players[i];
        const dx = (q.pos[0] - p.pos[0]) >> 16;
        const dy = (q.pos[1] - p.pos[1]) >> 16;
        const d2 = dx * dx + dy * dy;
        if (d2 < 50 * 50 or d2 > 900 * 900) continue;
        const rel = g.dirIndex(dx, dy);
        const diff = (@as(u32, rel) + 8 - @as(u32, p.facing)) % 8;
        if (diff > 1 and diff < 7) continue; // facing ±1 lane
        if (nearestOppDist2(m, opp, q.pos) < 40 * 40) continue;
        if (d2 < best.dist) best = .{ .i = @intCast(i), .dist = d2 };
    }
    return best;
}

fn dirCandidate(m: *MatchP, t: u1, idx: u5) u3 {
    _ = m;
    _ = t;
    _ = idx;
    return 0;
}

/// m.kick(kind=="shot") + OriginalShotState with this actor's skill.
fn shotLaunchAt(m: *MatchP, t: u1, idx: u5, dir: u3) void {
    const p = &m.teams[t].players[idx];
    ballMod.shotLaunch(&m.ball, dir, 80, &m.rng);
    m.ball.lastTeam = @intCast(t);
    m.ball.lastPlayer = @intCast(idx);
    m.ball.trappedBy = -1;
    p.touchCooldown = 15;
    if (m.teams[t].human) {
        m.aftertouch = .{ .lateral = 0, .vertical = 0, .ticks = 15 };
    }
    sfx.requestKick();
}

/// Tackle entry (original_controls's tackle state 12).
fn attemptTackle(m: *MatchP, t: u1, idx: u5) void {
    const taker = &m.teams[t].players[idx];
    const opp: u1 = if (t == 0) 1 else 0;
    if (m.ball.trappedBy < 0) return;
    const tt: u1 = @intCast(@divTrunc(m.ball.trappedBy, 11));
    if (tt != opp) return;
    const taker2 = distI2(taker.pos, m.ball.pos) <= 144;
    if (!taker2) return;
    taker.state = 12;
    taker.actionTicks = 20;
    taker.step = taker.pace * 2;
    // The tackled actor fumbles immediately (original_contact state 12).
    const tv = g.dirVec(taker.facing);
    m.ball.vel[0] = tv[0] * 8; // 8 units/step, the fumble
    m.ball.vel[1] = tv[1] * 8;
    m.ball.lift = 80000;
    m.ball.trappedBy = -1;
    sfx.requestContact();
}

// --------------------------------------------------------------------------
// KEEPER (original_keeper.go + original_keeper_release.go, simplified dive).
// --------------------------------------------------------------------------
fn stepKeeper(m: *MatchP, t: u1, p: *g.Player) void {
    advanceAnim(p);
    const attackDown = m.teams[t].attackDown;
    const goalY: i32 = if (attackDown) 6 else 1386; // own line: opposite the attack
    const ballX = g.unfix(m.ball.pos[0]);
    const ballY = g.unfix(m.ball.pos[1]);

    if (m.ball.trappedBy >= 0 and m.ball.trappedBy == @as(i16, @intCast(@as(u16, t) * 11))) {
        // CARRY: 50 ticks then release (keeper_hold / originalKeeperRelease).
        m.ball.pos = .{ p.pos[0], p.pos[1] - g.fx(2) };
        m.ball.vel = .{ 0, 0 };
        m.ballVisible = false;
        if (p.ownerTicks > 0) {
            p.ownerTicks -= 1;
            if (p.ownerTicks == 0) keeperRelease(m, t);
        }
        return;
    }

    // Positioning (original_keeper_target): stay on the line, x tracks ball.
    var targetX: i32 = g.clampI(ballX, 426, 486);
    if (ballX < 360 or ballX > 552) targetX = 456;
    const target: [2]i32 = .{ g.fx(targetX), g.fx(goalY) };
    setFacingTo(p, .{ g.unfix(m.ball.pos[0]), ballY });

    // Chase inside our box when the ball is slow and low.
    const dx = (m.ball.pos[0] - p.pos[0]) >> 16;
    const dy = (m.ball.pos[1] - p.pos[1]) >> 16;
    const d2 = dx * dx + dy * dy;
    const inOwnBox = if (attackDown) ballY < 216 else ballY > 1176;
    // Ball speed² in whole units: shift the 16.16 velocity BEFORE squaring, as
    // the other helpers do. Shifting the sum instead squares first (8 units/step
    // is 2.7e11) and wraps i32, so this test read garbage.
    const vx = m.ball.vel[0] >> 16;
    const vy = m.ball.vel[1] >> 16;
    const slow = vx * vx + vy * vy < 3;
    if (inOwnBox and d2 > 0 and slow and m.ball.trappedBy < 0) {
        moveBy(p, g.dirIndex(dx, dy), p.pace);
    } else {
        moveBy(p, g.dirIndex(target[0] - p.pos[0], target[1] - p.pos[1]), p.pace);
    }
    p.pos[1] = g.clampI(p.pos[1], g.fx(if (attackDown) 0 else 1300), g.fx(if (attackDown) 92 else 1392));
    p.pos[0] = g.clampI(p.pos[0], g.fx(400), g.fx(512));

    // Catch (originalKeeperCatch): dist² ≤ 144, height ≤ 12.
    if (m.ball.trappedBy < 0 and d2 <= 144 and m.ball.height <= g.fx(12)) {
        m.ball.trappedBy = @intCast(@as(u16, t) * 11);
        m.ball.vel = .{ 0, 0 };
        m.ball.height = 8 * g.FSCALE;
        p.ownerTicks = 50;
        p.state = 20;
        m.ballVisible = false;
    }
}

/// keeperRelease: pass to a goal-preferring receiver, else the clearance.
fn keeperRelease(m: *MatchP, t: u1) void {
    const p = &m.teams[t].players[0];
    const attackDown = m.teams[t].attackDown;
    const receiver = passTarget(m, t, 0);
    if (receiver < g.squad_size) {
        ballMod.passLaunch(&m.ball, m.teams[t].players[receiver].pos, p, 80, &m.rng);
        m.teams[t].players[receiver].ownerTicks = 100;
        sfx.requestKick();
    } else {
        // originalKeeperClearance: power = dist>>2 + 60 + rand%100, lift*700.
        // originalKeeperClearance aims at the far goal mouth: (456, 1352) for a
        // team attacking +y, (456, 40) the other way.
        const dir = g.dirIndex(g.fx(456) - m.ball.pos[0], g.fx(if (attackDown) 1352 else 40) - m.ball.pos[1]);
        const v = g.dirVec(dir);
        const w: u32 = m.rng.word();
        // SIMPLIFIED from power = sqrt(dist)>>2 + 60 (+rand): a long punt
        // upfield at 6-7 units/step with a high arc.
        const clear: i32 = @as(i32, 6) + @divTrunc(@as(i32, @intCast(@rem(w, 100))), 40);
        m.ball.vel[0] = v[0] * clear;
        m.ball.vel[1] = v[1] * clear;
        m.ball.lift = 150000;
        m.ball.trappedBy = -1;
        sfx.requestKick();
    }
    p.state = 19;
    m.ballVisible = true;
    m.ball.lastTeam = @intCast(t);
    m.ball.lastPlayer = 0;
}

// --------------------------------------------------------------------------
// CPU outfield actor (the dive chain + chase, originals trimmed to a friendly).
// --------------------------------------------------------------------------
fn stepAIField(m: *MatchP, t: u1, idx: u5, c: g.Control) void {
    _ = c;
    const p = &m.teams[t].players[idx];
    const opp: u1 = if (t == 0) 1 else 0;
    advanceAnim(p);
    if (p.state == 13) return;
    if (m.phase != .playing) {
        // Restart actors walk to their targets.
        walkTo(m, p, t, idx);
        return;
    }

    const hold = m.ball.trappedBy >= 0 and m.ball.trappedBy == @as(i16, @intCast(@as(u16, t) * 11 + idx));
    if (hold) {
        aiPossession(m, t, idx, p);
        return;
    }

    // The nearest teammate chases the ball, others hold their zone.
    const nearest = nearestOfTeam(m, t);
    if (idx == nearest) {
        // Chase CLOSES the whole way: the original's contact distance is
        // PlayerRadius+BallRadius (~10 px), so there is no standing dead zone.
        const bx = m.ball.pos[0] - p.pos[0];
        const by = m.ball.pos[1] - p.pos[1];
        const d2 = (bx >> 16) * (bx >> 16) + (by >> 16) * (by >> 16);
        if (d2 > 96) {
            moveBy(p, g.dirIndex(bx, by), p.pace);
        } else if (p.touchCooldown == 0 and m.ball.trappedBy < 0 and m.ball.height <= g.fx(2)) {
            // The original's interception: a reachable ground ball is HELD
            // (glued); the glue feeds aiPossession next step.
            m.ball.trappedBy = @intCast(@as(u16, t) * 11 + idx);
        } else if (p.touchCooldown == 0 and m.ball.trappedBy < 0 and m.ball.height <= g.fx(12)) {
            const dir = g.dirIndex(bx, by);
            ballMod.dribbleLaunch(&m.ball, dir, p.pace);
            m.ball.lastTeam = @intCast(t);
            m.ball.lastPlayer = @intCast(idx);
            p.touchCooldown = 15;
            p.ownerTicks = 300;
            sfx.requestKick();
        }
        // CPU tackle attempt on the opposing carrier (originalAIContact).
        if (m.ball.trappedBy >= 0 and @as(u1, @intCast(@divTrunc(m.ball.trappedBy, 11))) == opp and d2 <= 1600) {
            const w: u32 = m.rng.word();
            if (w % 1500 < 12) attemptTackle(m, t, idx);
        }
        return;
    }
    // Tactic slot, ball-biased (original_data TacticPosition).
    const slot = g.tacticPos(t, idx, g.unfix(m.ball.pos[0]), g.unfix(m.ball.pos[1]), m.teams[t].attackDown);
    targetAt(m, p, t, .{ g.fx(slot[0]), g.fx(slot[1]) });

    // AI header: height>16, near, 2% per tick (originalAIJump).
    if (m.ball.height > g.fx(16) and dist2Ball(p, m) <= 900) {
        const w: u32 = m.rng.word();
        if (w % 10000 <= 200) {
            p.state = 13;
            p.jumpTicks = 44;
            p.actionTicks = 44;
        }
    }
}

fn nearestOfTeam(m: *MatchP, t: u1) u8 {
    var best: u8 = 255;
    var bd: i32 = 1 << 30;
    for (1..g.squad_size) |i| {
        const d2 = distI2(m.teams[t].players[i].pos, m.ball.pos);
        if (d2 < bd) {
            bd = d2;
            best = @intCast(i);
        }
    }
    return best;
}

/// Movement toward target with the source's 16-sector heading hysteresis
/// reduced to keep a running pace (originalTargetHeading hysteresis).
fn targetAt(m: *MatchP, p: *g.Player, t: u1, target: [2]i32) void {
    _ = m;
    _ = t;
    const dx = target[0] - p.pos[0];
    const dy = target[1] - p.pos[1];
    const d2 = (dx >> 16) * (dx >> 16) + (dy >> 16) * (dy >> 16);
    if (d2 < 20 * 20) {
        p.step = 0;
        setFacingTo(p, target);
        return;
    }
    moveBy(p, g.dirIndex(dx, dy), p.pace);
}

/// Restart walkers (restarts.go updateRestart): while play is stopped the
/// squad jogs to its ball-biased tactic slots; the taker is already placed by
/// beginRestart and steps from there.
fn walkTo(m: *MatchP, p: *g.Player, t: u1, idx: usize) void {
    if (m.ball.trappedBy >= 0) return; // the taker's ball: stand
    const slot = g.tacticPos(t, idx, g.unfix(m.ball.pos[0]), g.unfix(m.ball.pos[1]), m.teams[t].attackDown);
    targetAt(m, p, t, .{ g.fx(slot[0]), g.fx(slot[1]) });
}

/// The CPU's in-possession chain (original_pass.go updateOriginalAIOwner).
fn aiPossession(m: *MatchP, t: u1, idx: u5, p: *g.Player) void {
    const attackDown = m.teams[t].attackDown;
    const opp: u1 = if (t == 0) 1 else 0;
    const goalY: i32 = if (attackDown) 1416 else -24;
    const dx = (g.fx(456) - p.pos[0]) >> 16;
    const dy = (g.fx(goalY) - p.pos[1]) >> 16;
    const d2goal = dx * dx + dy * dy;

    const tvf = g.dirVec(p.facing); // glued at the feet, in front
    m.ball.pos = .{ p.pos[0] + tvf[0] * 8, p.pos[1] + tvf[1] * 8 };
    m.ball.vel = .{ 0, 0 };

    // Shoot from inside range — or a rare long chance. Outside, pass when a
    // lane opens; otherwise dribble at the goal mouth.
    var w: u32 = m.rng.word();
    if (d2goal < 14400 or w % 240 == 0) {
        const k = &m.teams[opp].players[0];
        var aimX: i32 = 456;
        if (k.pos[0] >= g.fx(456)) aimX = 432 else aimX = 480;
        const aimDir = g.dirIndex((g.fx(aimX) - m.ball.pos[0]) >> 16, (g.fx(goalY) - m.ball.pos[1]) >> 16);
        shotLaunchAt(m, t, idx, aimDir);
        return;
    }
    // Pass when a teammate target exists (possessionLane's pass priority).
    w = m.rng.word();
    if (w % 100 < 10) {
        const target = trapPassTarget(m, t, idx);
        if (target.i < g.squad_size) {
            ballMod.passLaunch(&m.ball, m.teams[t].players[target.i].pos, p, 80, &m.rng);
            m.teams[t].players[target.i].ownerTicks = 100;
            p.state = 30;
            p.actionTicks = 16;
            sfx.requestKick();
            return;
        }
    }
    // Otherwise dribble toward the goal mouth at 456,70|1322.
    const dir = g.dirIndex(g.fx(456) - m.ball.pos[0], g.fx(if (attackDown) 1322 else 70) - m.ball.pos[1]);
    ballMod.dribbleLaunch(&m.ball, dir, p.pace);
    p.touchCooldown = 15;
    sfx.requestKick();
}

pub fn updateHumanAftertouch(m: *MatchP, c: g.Control) void {
    if (m.aftertouch.ticks == 0) return;
    if (c.dir != 8) {
        const idx = m.teams[0].controlled;
        const laun: u3 = m.teams[0].players[idx].facing;
        _ = ballMod.shotAftertouch(&m.ball, laun, @truncate(c.dir));
    }
    m.aftertouch.ticks -= 1;
}

pub fn distI2(a: [2]i32, b: [2]i32) i32 {
    const dx = (a[0] - b[0]) >> 16;
    const dy = (a[1] - b[1]) >> 16;
    return dx * dx + dy * dy;
}

// Tactic-position walks during restarts (restarts.go updateRestart): in the
// curated cart these are the "wait for host fire" ticks; the countdown is
// driven by tick(). Filler logic lives in tick(), not a walk anywhere.
