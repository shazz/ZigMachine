// --------------------------------------------------------------------------
// Kickoff2 — the ball: OriginalBallStep's per-tick integration, kick/shot/
// pass launches, the state-44 aftertouch actor and the goal frame. Transcribed
// from internal/engine/original_physics.go, original_pass.go, ball.go and
// original_goal_frame.go, all of which keep the source's integer words.
// --------------------------------------------------------------------------
const std = @import("std");
const g = @import("gs.zig");

pub const Event = struct {
    kick: bool = false,
    bounce: i16 = 0, // 0 none; 1..4 the bounce sample to play
    post: bool = false,
    whistle: bool = false, // goal scored (schedule the whistle + crowd)
    contact: bool = false,
};

const PITCH_V: u5 = 2; // Normal pitch: vertical restitution
const PITCH_P: u5 = 5; // ...and planar friction shifts

/// OriginalBallStep (original_physics.go:20-49) — exact integer ops.
pub fn step(state: *g.Ball, gf: *g.GoalFrame, windX: i32, windY: i32, ev: *Event) void {
    if (state.curve != 0) {
        state.vel[1] += state.curve;
        state.curve -= state.curve >> 4;
        state.curve -= 1;
    }
    state.lift -= 0xd84; // gravity: -(5456/65536) ≈ -83.2 units/s²
    if (state.height >> 16 > 4) {
        state.vel[0] += (windX - state.vel[0]) >> 7;
        state.vel[1] += (windY - state.vel[1]) >> 7;
    }
    state.lift += (-state.lift) >> 7; // air drag on the vertical
    state.height += state.lift;
    if (state.height < 0) {
        state.lift = -state.lift;
        state.height += state.lift; // restore the pre-impact height
        // Normal pitch: vertical restitution 2, planar friction 5.
        state.lift -= state.lift >> PITCH_V;
        state.vel[0] -= state.vel[0] >> PITCH_P;
        state.vel[1] -= state.vel[1] >> PITCH_P;
        const audible = state.lift >= 0x8000;
        if (audible) {
            // One step's bounce lifts by at most ~2/65536 units: sample 1..4.
            const in: i64 = @as(i64, state.lift) * 2;
            const n: i16 = @intCast(std.math.clamp(in >> 16, 0, 3) + 1);
            ev.bounce = n;
        }
    }
    state.pos[0] += state.vel[0];
    state.pos[1] += state.vel[1];
    _ = gf;
}

/// Ball speed-squared cache (ball.go:127-131): the heading guide mirrors y.
pub fn ballHeadingGuide(ball: *const g.Ball) [2]i32 {
    const x = g.unfix(ball.pos[0]);
    var y = g.unfix(ball.pos[1]);
    if (y >= 696) y = 1392 - y; // mirror for the guide (originalGoalGuide)
    return .{ x + y, x - y };
}

// --------------------------------------------------------------------------
// Launches. All velocities are displacement per 50 Hz step in 16.16.
// --------------------------------------------------------------------------

/// m.kick for SHOT (ball.go:5-52 + originalShot → OriginalShotState).
/// skill 0..100 (Go's Shooting*100). rng = the match's own generator.
pub fn shotLaunch(ball: *g.Ball, dir: u3, skill: i32, rng: *g.Rng) void {
    const base = g.dirVec(dir);
    const perp = g.dirVec(@truncate((@as(u32, dir) + 2) & 7));
    const skillc = g.clampI(skill, 0, 100);
    var lateral: i32 = 0;
    var lift: i32 = 108;
    var sign: i32 = 1;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const w: i32 = rng.word();
        lateral += sign * @rem(w, 110 - skillc);
        sign = -sign;
    }
    lateral *= 4;
    sign = 1;
    i = 0;
    while (i < 4) : (i += 1) {
        const w: i32 = rng.word();
        lift += sign * @rem(w, 101 - skillc);
        sign = -sign;
    }
    ball.vel[0] = base[0] * 8 + @divTrunc(perp[0] * lateral, 8192);
    ball.vel[1] = base[1] * 8 + @divTrunc(perp[1] * lateral, 8192);
    ball.lift = lift * 1000;
    ball.trappedBy = -1;
}

/// OriginalPassState (original_pass.go:7-34): power toward a receiver, in
/// units/step proportional to the pass distance (long = harder, capped).
pub fn passLaunch(ball: *g.Ball, target: [2]i32, passer: *const g.Player, skill: i32, rng: *g.Rng) void {
    const dx = target[0] + errWord(rng, skill, false) - passer.pos[0];
    const dy = target[1] + errWord(rng, skill, true) - passer.pos[1];
    // Units director (1.0 = FSCALE), kept to the i32 range at 350-unit passes.
    const dist: i32 = @max(1, distI(passer.pos, target));
    const nx = @divTrunc(@divTrunc(dx, g.FSCALE) * 32768, dist) * 2;
    const ny = @divTrunc(@divTrunc(dy, g.FSCALE) * 32768, dist) * 2;
    const speed: i32 = std.math.clamp(@divTrunc(dist, 8), 2, 9);
    ball.vel[0] = nx * speed;
    ball.vel[1] = ny * speed;
    const w: u32 = rng.word();
    ball.lift = (200 + @as(i32, @intCast(w % 100))) * 200;
    ball.trappedBy = -1;
}

fn errWord(rng: *g.Rng, skill: i32, y: bool) i32 {
    const den = 128 * (100 - g.clampI(skill, 0, 100)) + 1;
    var acc: i32 = 0;
    var i: usize = 0;
    var base: usize = 0;
    while (i < 4) : (i += 1) {
        base = if (y) i + 4 else i;
        acc += @intCast(rng.word() % @as(u32, @intCast(den)));
    }
    return (acc - 2 * (den - 1)) << 2;
}

/// OriginalDribbleState (original_physics.go:208-212) — the touch that
/// pushed the ball ahead of a running player: a hair above the runner's pace.
pub fn dribbleLaunch(ball: *g.Ball, dir: u3, pace: i32) void {
    const speed: i32 = std.math.clamp((pace >> 16) + 1, 2, 6); // units/step
    const v = g.dirVec(dir);
    ball.vel[0] = v[0] * speed;
    ball.vel[1] = v[1] * speed;
    ball.lift = 40000;
    ball.trappedBy = -1;
}

/// OriginalAftertouchImpulse (original_physics.go:216-228) — the charged
/// free-kick/arm: `lateral` (units/1024) bends the flight, `vertical` the lift.
pub fn aftertouchImpulse(ball: *g.Ball, dir: u3, lateral: i32, vertical: i32) void {
    const lat = std.math.clamp(lateral, -900, 900);
    const d: u3 = if (lat < 0) dir -| 2 else dir +| 2;
    const v = g.dirVec(d);
    ball.vel[0] += @divTrunc(v[0] * lat, 8192);
    ball.vel[1] += @divTrunc(v[1] * lat, 8192);
    ball.lift -= vertical * 200;
}

/// OriginalShotAftertouchImpulse (original_physics.go:234-245) — the regular
/// shot's aftertouch: turn ±2 sectors away from the launch heading, push
/// velocity 10000 that way and bias lift vertically.
pub fn shotAftertouch(ball: *g.Ball, launchDir: u3, inputDir: u3) bool {
    const rel = (@as(u32, inputDir) + 8 - @as(u32, launchDir)) % 8;
    const turn = if (rel == 0 or rel == 4) null else switch (rel) {
        1, 2, 3 => @as(u3, 2),
        5, 6, 7 => @as(u3, 6),
        else => null,
    };
    const verticals = [8]i32{ -600, -600, 0, 1000, 1000, 1000, 0, -600 };
    const vertical = verticals[rel];
    if (turn == null and vertical == 0) return false;
    if (turn) |t| {
        const vd: u3 = @truncate((@as(u32, launchDir) + t) & 7);
        const v = g.dirVec(vd);
        ball.vel[0] += @divTrunc(v[0] * 10000, g.FSCALE);
        ball.vel[1] += @divTrunc(v[1] * 10000, g.FSCALE);
    }
    ball.lift += vertical * 10;
    return true;
}

// --------------------------------------------------------------------------
// The goal frame (original_goal_frame.go). Everything from x<404 / posts to
// the 10-contact goal decision, with the sequential signed reflection.
// --------------------------------------------------------------------------
const colAngles = [9][2]i32{
    .{ -10000, 0 }, .{ -1250, -9922 }, .{ 5000, -8660 }, .{ 8750, -4842 },
    .{ 10000, 0 },  .{ 8750, 4842 },  .{ 5000, 8660 },  .{ -1250, 9922 },
    .{ -10000, 0 },
};

fn frameReflection(first: i32, second: i32, angle: usize) [2]i32 {
    const pair = colAngles[angle];
    // The original's sequential MULS/DIVS work on the low 16-bit words
    // (which is what the Go's std.math.cast(i16, ...) captured): first'
    // feeds the second product as a word operand.
    const f0: i16 = @truncate(first >> 6);
    const s0: i16 = @truncate(second >> 6);
    const f: i32 = @as(i32, @intCast(@divTrunc(@as(i64, f0) * pair[0] + @as(i64, s0) * pair[1], 10000))) << 6;
    const fb: i16 = @truncate(f);
    const s: i32 = @as(i32, @intCast(@divTrunc(@as(i64, s0) * pair[0] - @as(i64, fb) * pair[1], 10000))) << 6;
    return .{ f, s };
}

/// OriginalGoalFrameStep. previousY is the y BEFORE this step's integration.
pub fn goalFrameStep(ball: *g.Ball, gf: *g.GoalFrame, previousY: i32, ev: *Event) bool {
    _ = ev;
    const x = std.math.cast(i16, g.unfix(ball.pos[0])) orelse return false;
    const y = std.math.cast(i16, g.unfix(ball.pos[1])) orelse return false;
    const height = std.math.cast(i16, g.unfix(ball.height)) orelse return false;

    if (@as(u16, @bitCast(x)) >= 912) {
        if (gf.outKind == 0) {
            gf.outKind = 1;
            gf.outX = x;
            gf.outY = @intCast(previousY >> 16);
        }
    } else if (gf.outKind == 1) {
        gf.outKind = 0;
    }

    if (@as(u16, @bitCast(y)) < 1392) {
        gf.contactMask = 0;
        gf.contactTicks = 0;
        gf.contactCooldown = 0;
        if (gf.outKind == 2) gf.outKind = 0;
        return false;
    }
    if (y <= -64 or y >= 1456) {
        ball.vel[0] = 0;
        ball.vel[1] = 0;
        return false;
    }

    if (gf.outKind == 3 or gf.outKind == 4) {
        // Inside the net.
        if (y <= -19 or y >= 1410) {
            ball.vel[0] >>= 1;
            ball.vel[1] = 0;
        }
        if (x < 412 or x >= 500) {
            ball.vel[0] = 0;
            ball.vel[1] >>= 1;
        }
        if (height >= 28) ball.lift = -ball.lift;
        return false;
    }

    if (gf.outKind == 2) {
        if (y < -24 or y > 1416 or x < 404 or x > 508 or height > 36) return false;
        if (x >= 412 and x <= 500) {
            if (height < 32) {
                ball.vel[0] = 0;
                ball.vel[1] = 0;
            } else {
                ball.height -= ball.lift;
                ball.lift = (-ball.lift) >> 2;
                if (y > 696) ball.vel[1] += 20000 else ball.vel[1] -= 20000;
            }
        } else {
            ball.pos[0] -= ball.vel[0];
            ball.vel[0] = (-ball.vel[0]) >> 2;
        }
        return false;
    }

    if (y <= 1402 and y >= -10 and gf.contactCooldown > 0) {
        gf.contactCooldown -= 1;
        return false;
    }

    // endOut path
    if (x < 404 or x > 508 or height > 36) {
        if (gf.outKind == 0) {
            gf.outKind = 2;
            gf.outX = x;
            gf.outY = y;
        }
        return false;
    }
    // the goal mouth
    if (x > 412 and x < 500 and height < 28) {
        gf.outKind = if (y < 0) 3 else 4;
        if (gf.endsSwapped) gf.outKind ^= 7;
        return false; // silent goal (the match code adds the whistle)
    }

    var sound = false;
    var half = false;
    if (height >= 28 and gf.contactMask & 4 == 0) {
        gf.contactMask |= 4;
        const r = frameReflection(ball.lift, ball.vel[1], @as(usize, @as(u32, @intCast(@max(0, height - 28))) & 7));
        ball.lift = r[0];
        ball.vel[1] = r[1];
        if (y < 0) ball.lift = -ball.lift;
        half = true;
    }
    var angle: i32 = -1;
    if (x <= 412 and gf.contactMask & 2 == 0) {
        gf.contactMask |= 2;
        angle = x - 404;
    } else if (x >= 500 and gf.contactMask & 1 == 0) {
        gf.contactMask |= 1;
        angle = x - 500;
    }
    if (angle >= 0) {
        const r = frameReflection(ball.vel[0], ball.vel[1], @intCast(angle & 7));
        ball.vel[0] = r[0];
        ball.vel[1] = r[1];
        if (y < 0) ball.vel[0] = -ball.vel[0];
        half = true;
    }
    if (half) {
        ball.vel[0] -= ball.vel[0] >> 1;
        ball.vel[1] -= ball.vel[1] >> 1;
        ball.lift -= ball.lift >> 1;
        gf.contactCooldown = 4;
        sound = true;
    }
    gf.contactTicks += 1;
    if (gf.contactTicks >= 10) {
        if (x < 410 or x > 502 or height > 30) {
            if (gf.outKind == 0) {
                gf.outKind = 2;
                gf.outX = x;
                gf.outY = y;
            }
            return sound;
        }
        gf.outKind = if (y < 0) 3 else 4;
        if (gf.endsSwapped) gf.outKind ^= 7;
        return sound;
    }
    return sound;
}

fn sqrtU32(xin: u32) u32 {
    // Hacker's Delight isqrt — no float, exact floor(sqrt).
    var x = xin;
    var m: u32 = 0x40000000;
    var y: u32 = 0;
    while (m != 0) : (m >>= 2) {
        const b: u32 = y | m;
        y >>= 1;
        if (x >= b) {
            x -= b;
            y |= m;
        }
    }
    return y;
}

pub inline fn distI(a: [2]i32, b: [2]i32) i32 {
    // Integer sqrt for the pass power — units in, units out (no float: the
    // per-frame path is integer-only on this machine).
    const dx: i32 = (a[0] - b[0]) >> 16;
    const dy: i32 = (a[1] - b[1]) >> 16;
    const sq: u32 = @intCast(@max(0, dx * dx + dy * dy));
    return @intCast(sqrtU32(sq));
}
