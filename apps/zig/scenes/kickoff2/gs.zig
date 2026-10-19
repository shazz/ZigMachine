// --------------------------------------------------------------------------
// Kick Off 2 — the curated friendly: England vs Spain, one match, 1P (left
// team) vs CPU. Ported from the olivierh59500 Go/Ebitengine remake of Dino
// Dini's original, whose internal/engine package is a cycle-faithful
// transcription of the Amiga 68000 source. This module carries the shared
// world state and the constants transcribed from internal/engine/types.go
// (originalFixedScale = 65536; positions, velocities and heights are Q16.16
// i32 in pitch units, exactly as the source words were).
//
// No float in the per-frame path: the Go remake's float64s re-derive from
// these very 16.16 words, so porting keeps its integers and drops its casts.
// --------------------------------------------------------------------------
const std = @import("std");
const tac = @import("../../assets/screens/kickoff2/tactics.zig");

pub const TPS: u32 = 50; // PAL ticks per second
pub const FSCALE: i32 = 65536; // one pitch unit in Q16.16 words

pub const PitchWidth: i32 = 912;
pub const PitchHeight: i32 = 1392;
pub const GoalWidth: i32 = 96;
pub const GoalHeight: i32 = 24;
pub const PlayerRadius: i32 = 7;
pub const BallRadius: i32 = 3;
pub const PenaltyAreaWidth: i32 = 528;
pub const PenaltyAreaDepth: i32 = 216;
pub const GoalAreaWidth: i32 = 240;
pub const GoalAreaDepth: i32 = 72;
pub const CenterCircleRadius: i32 = 126;

// Original camera window: its scroll world is 960x1312 ground px; the visible
// window is 320 wide and (in the Go layout) 224 tall.
pub const GroundWidth: i32 = 960;
pub const GroundHeight: i32 = 1312;
pub const HalfWindowX: i32 = 192;
pub const HalfWindowY: i32 = 80;

pub const Fixed = i32;

pub inline fn fx(v: i32) Fixed {
    return v * FSCALE;
}
pub inline fn unfix(v: Fixed) i32 {
    return v >> 16;
}

/// Q16.16 multiply (a and b both in 16.16).
pub inline fn fmul(a: Fixed, b: Fixed) Fixed {
    return @intCast((@as(i64, a) * b) >> 16);
}
/// Divide a fixed by an integer-ish count preserving 16.16.
pub inline fn fdiv(a: Fixed, b: Fixed) Fixed {
    return @intCast((@as(i64, a) << 16) / @max(1, b));
}
pub inline fn clampF(v: Fixed, lo: Fixed, hi: Fixed) Fixed {
    return @min(hi, @max(lo, v));
}

pub fn clampI(v: i32, lo: i32, hi: i32) i32 {
    return @min(hi, @max(lo, v));
}

// --------------------------------------------------------------------------
// The original three-word LFSR (original_random.go, word order 0x16922).
// --------------------------------------------------------------------------
pub const Rng = struct {
    state: [3]u16 = .{ 0x2ae2, 0x6aed, 0x1337 },

    pub fn word(self: *Rng) u16 {
        var carry: u16 = (((self.state[1] >> 3) ^ self.state[2]) & 1);
        for (&self.state) |*s| {
            const next: u16 = s.* >> 15;
            s.* = (s.* << 1) | carry;
            carry = next;
        }
        return self.state[0];
    }
};

// --------------------------------------------------------------------------
// The eight movement directions (original_physics.go OriginalDirection).
// Diagonals are 0.707 — NOT renormalized (original_physics.go:97-99).
// --------------------------------------------------------------------------
pub const diag = 46341; // 0.7071 in 16.16 (the Go's 707/1000, NOT renormalized)
pub const one = FSCALE; // 1.0 in 16.16

pub fn dirVec(d: u3) [2]i32 {
    return switch (d) {
        0 => .{ 0, -one }, // N
        1 => .{ diag, -diag }, // NE
        2 => .{ one, 0 }, // E
        3 => .{ diag, diag }, // SE
        4 => .{ 0, one }, // S
        5 => .{ -diag, diag }, // SW
        6 => .{ -one, 0 }, // W
        7 => .{ -diag, -diag }, // NW
    };
}

/// OriginalDirectionIndex: the 2:1 octant thresholds (original_physics.go:102).
pub fn dirIndex(dx: i32, dy: i32) u3 {
    const ax = @abs(dx);
    const ay = @abs(dy);
    if (2 * ax < ay) return if (dy < 0) 0 else 4;
    if (2 * ay < ax) return if (dx < 0) 6 else 2;
    if (dx < 0) return if (dy > 0) 5 else 7;
    return if (dy > 0) 3 else 1;
}

// --------------------------------------------------------------------------
// Kits — from kit.go's 20-entry table at 0x17264 and defaults at 0x170ea.
// England (index 2: style 1, shirt 4 = white, shorts 1 = dark blue);
// Spain (index 3: style 1, shirt 9 = red, shorts 1 = dark blue). Both style-1
// sheets: squad A draws from style1a, squad B from style1b. ST-nibble RGB.
// --------------------------------------------------------------------------
pub const kitWhite = (15 * 17);
pub const kitNavy = (10 * 17); // 0x00a word blue nibble
pub const kitRed = (10 * 17);

// --------------------------------------------------------------------------
// Tactic positions: the original zone lookup (original_data.go 58-80). The
// raw files face downwards; team B mirrors X and Y and flips the zone.
// --------------------------------------------------------------------------
pub const bal = tac.tactic_balanced;

pub fn tacticPos(team: u1, player: usize, ballX: i32, ballY: i32, attackDown: bool) [2]i32 {
    const pi: usize = @intCast(clampI(@as(i32, @intCast(player)), 1, 10) - 1);
    const column = clampI(@divTrunc(ballX, 304), 0, 2);
    const row = clampI(@divTrunc(ballY, 348), 0, 3);
    var zone: i32 = column * 4 + row;
    if (!attackDown) zone = 11 - zone;
    const zi: usize = @intCast(zone);
    var tx: i32 = bal.targets[pi][zi][0];
    var ty: i32 = bal.targets[pi][zi][1];
    if (!attackDown) {
        ty = PitchHeight - ty;
        tx = PitchWidth - tx;
    }
    _ = team; // both teams use `balanced`; team B is reflected by attackDown
    return .{ tx, ty };
}

// --------------------------------------------------------------------------
// The two squads. Names from the original squads: the eleven starters.
// --------------------------------------------------------------------------
pub const TeamA = [_][]const u8{ "BUTCHER", "WRIGHT", "PEARCE", "GASCOIGNE", "LINEKER", "MERCER", "SANSOM", "ROBSON", "BEARDSLEY", "BARNES", "SPEED" };
pub const TeamB = [_][]const u8{ "ZUBIZARRETA", "MICHEL", "CAMINERO", "BAKKERO", "BUTRAGENO", "MANOLO", "GOIKOETXEA", "SOLER", "MARTIN", "HIERRO", "Salinas" };

// --------------------------------------------------------------------------
// One footballer. The fields carry the simulation state of the source words.
// --------------------------------------------------------------------------
pub const Player = struct {
    pos: [2]Fixed = .{ 0, 0 },
    facing: u3 = 4, // face south (down the pitch) by default
    step: i32 = 0, // Q16.16 displacement per tick (0 = standing)
    pace: i32 = 0, // fixed pace word (16.16)
    paceFixed: i32 = 0, // the source's fatiguing pace word
    keeper: bool = false,
    // The original action state; see players.zig's state list.
    state: i32 = 0,
    substate: i32 = 0,
    actionTicks: i32 = 0, // >0 draws the kick pose row (88+dir)
    animPhase: u16 = 0,
    jumpTicks: i32 = 0,
    ownerTicks: i32 = 0, // possession hold (300 on dribble launch, 200 claim)
    touchCooldown: i32 = 0,
    visible: bool = true,
    // Per-actor AI bookkeeping.
    target: [2]Fixed = .{ 0, 0 },
    chase: bool = false,
    dirHistory: u4 = 0, // the 16-sector heading hysteresis state
    spriteIndexOverride: ?u32 = null, // throw/celebration/keeper poses
};

pub const squad_size = 11;

// --------------------------------------------------------------------------
// Control: one actor's per-tick input (the Go Input.{Move, Fire} directly).
// dir is 0..7 or 8 for "no direction"; fire is the raw button state.
// --------------------------------------------------------------------------
pub const Control = struct {
    dir: u8 = 8,
    fire: bool = false,
    fireRising: bool = false, // this tick's rising edge
    switchPressed: bool = false,
};

// --------------------------------------------------------------------------
// The ball. OriginalBallState words (original_physics.go:10-14).
// --------------------------------------------------------------------------
pub const Ball = struct {
    pos: [2]Fixed = .{ fx(456), fx(696) },
    vel: [2]Fixed = .{ 0, 0 }, // displacement per 50 Hz step
    height: Fixed = 0,
    lift: Fixed = 0, // vertical velocity per step
    curve: i32 = 0,
    lastTeam: i8 = -1,
    lastPlayer: i8 = -1,
    trappedBy: i16 = -1, // team*11+player, or -1
};

// Goal-frame words (original_goal_frame.go OriginalGoalFrameState).
pub const GoalFrame = struct {
    contactMask: u8 = 0,
    contactTicks: i16 = 0,
    contactCooldown: i16 = 0,
    outKind: i16 = 0, // 0 none, 1 side-out, 2 end-out, 3/4 goals
    outX: i16 = 0,
    outY: i16 = 0,
    endsSwapped: bool = false,
};

pub const RestartKind = enum { kickoff, goal_kick, corner, throw_in, after_goal };

pub const Restart = struct {
    active: bool = false,
    kind: RestartKind = .kickoff,
    team: u1 = 0,
    taker: u5 = 0, // player index of the taking team
    pos: [2]Fixed = .{ 0, 0 },
    countdown: i32 = 0,
    charge: i32 = 0,
    armed: bool = false,
    choice: u4 = 0, // corner direction choice 0..8 (456-centred panel)
};

pub const Phases = enum { front, kickoff_wait, playing, goal_pause, half_time, full_time };

pub const half_seconds: u32 = 300; // 5-min halves at PAL speed
pub const half_limit: u32 = half_seconds * TPS;
