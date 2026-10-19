// --------------------------------------------------------------------------
// BUBBLE BOBBLE — the arcade simulation, ported from the olivierh59500 Go
// remake's internal/game (game.go, physics.go, bubbles.go, enemies.go,
// items.go, level.go) to FIXED POINT: every float64 position/velocity in the
// Go is Q16.16 here (Fx), the Go's math.Sin/Cos are the cart's integer sine
// table, and the dynamic slices are fixed-capacity arrays.
//
// The Go runs its world at 60 ticks a second on a 768x624 playfield
// (32x26 tiles of 24px, ActorSize 44); the scene drives this at the same 60 Hz
// with an accumulator over the ST's 50 Hz frame, so speeds stay the Go's.
//
// No rendering and no float in any per-frame path: this file is the game.
// --------------------------------------------------------------------------
const std = @import("std");
const trig = @import("zigos").fixtrig;
const assets = @import("assets.zig");

pub const COLUMNS: i32 = 32;
pub const ROWS: i32 = 26;
pub const TILE: i32 = 24;
pub const WIDTH: i32 = COLUMNS * TILE; // 768
pub const HEIGHT: i32 = ROWS * TILE; // 624
pub const TPS: i32 = 60;
pub const ACTOR: i32 = 44;
pub const ONE: Fx = 1 << 16;
pub const Fx = i32;

/// Compile-time float -> Q16.16 (constants only; nothing at run time).
inline fn fx(comptime v: f64) Fx {
    return @intFromFloat(v * 65536.0);
}

inline fn mul(a: Fx, b: Fx) Fx {
    return @intCast((@as(i64, a) * @as(i64, b)) >> 16);
}

/// floor(v) in whole pixels, the way Go's int(math.Floor(v/Tile)) does.
inline fn toInt(v: Fx) i32 {
    return v >> 16;
}

inline fn ceilPx(v: Fx) i32 {
    const a: i64 = if (v < 0) -@as(i64, v) else @as(i64, v);
    const n: i32 = @intCast((a + 65535) >> 16);
    return if (v < 0) -n else n;
}

inline fn absFx(v: Fx) Fx {
    return if (v < 0) -v else v;
}

inline fn clamp(v: Fx, lo: Fx, hi: Fx) Fx {
    return if (v < lo) lo else if (v > hi) hi else v;
}

inline fn maxI(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}
inline fn minI(a: i32, b: i32) i32 {
    return if (a < b) a else b;
}
inline fn maxFx(a: Fx, b: Fx) Fx {
    return if (a > b) a else b;
}
inline fn minFx(a: Fx, b: Fx) Fx {
    return if (a < b) a else b;
}

inline fn intersects(x: Fx, y: Fx, w: i32, h: i32, xx: Fx, yy: Fx, ww: i32, hh: i32) bool {
    return x < xx + (ww << 16) and x + (w << 16) > xx and y < yy + (hh << 16) and y + (h << 16) > yy;
}

inline fn direction(n: Fx) i32 {
    return if (n < 0) -1 else 1;
}

// --- types ----------------------------------------------------------------
pub const EnemyKind = enum(u8) { zenchan = 0, monsta = 1, mighta = 2, pulpul = 3, banebou = 4, invader = 5 };
pub const Element = enum(u8) { none = 0, water = 1, thunder = 2, fire = 3 };
pub const PowerUp = enum(u8) {
    none = 0,
    pink_candy = 1,
    blue_candy = 2,
    yellow_candy = 3,
    shoes = 4,
    orange_parasol = 5,
    red_parasol = 6,
    purple_parasol = 7,
    crystal_ring = 8,
    amethyst_ring = 9,
    ruby_ring = 10,
    dynamite = 11,
    clock = 12,
};
pub const State = enum(u8) { ready, playing, clearing, game_over, won };
pub const EnemyState = enum(u8) { active, trapped, defeated, carried };
pub const Sound = enum(u8) { shoot, jump, pop, death, food, item, fire, water, explosion, laser };

pub const Cell = struct { col: i32, row: i32 };

/// Cell coordinates name the platform underneath an actor's feet.
pub const Point = struct { x: Fx, y: Fx };

pub fn cellPosition(c: Cell, size: i32) Point {
    return .{
        .x = @min(c.col * TILE, WIDTH - 2 * TILE - size) << 16,
        .y = @max(TILE, c.row * TILE - size) << 16,
    };
}

pub const Body = struct { x: Fx = 0, y: Fx = 0, vx: Fx = 0, vy: Fx = 0, ground: bool = false };

pub const Powers = struct {
    pink: bool = false,
    blue: bool = false,
    yellow: bool = false,
    shoes: bool = false,
    crystal: bool = false,
    amethyst: bool = false,
    ruby: bool = false,
    walk_points: Fx = 0,
};

pub const Player = struct {
    body: Body = .{},
    lives: i32 = 3,
    jump_buffer: i32 = 0,
    coyote: i32 = 0,
    last_jump: bool = false,
    dir: i32 = 1,
    invincible: i32 = 0,
    dead: i32 = 0,
    shoot: i32 = 0,
    cooldown: i32 = 0,
    walk_frame: i32 = 0,
    power: Powers = .{},

    pub fn alive(self: Player) bool {
        return self.lives > 0 and self.dead == 0;
    }
};

pub const Enemy = struct {
    body: Body = .{},
    carried_by: i32 = 0,
    carry_ticks: i32 = 0,
    id: i32 = 0,
    kind: EnemyKind = .zenchan,
    state: EnemyState = .active,
    dir: i32 = -1,
    vertical: i32 = 1,
    angry: bool = false,
    age: i32 = 0,
    cooldown: i32 = 0,
    shoot: i32 = 0,
    dead_ticks: i32 = 0,
    phase: trig.Angle = 0,
};

pub const Bubble = struct {
    body: Body = .{},
    id: i32 = 0,
    dir: i32 = 1,
    age: i32 = 0,
    enemy_id: i32 = 0,
    captured_age: i32 = 0,
    distance: i32 = 0,
    max_distance: i32 = 200,
    speed: i32 = 8,
    floating: bool = false,
    removed: bool = false,
    element: Element = .none,
};

pub const Projectile = struct {
    body: Body = .{},
    laser: bool = false,
    age: i32 = 0,
    removed: bool = false,
};

pub const Item = struct {
    body: Body = .{},
    stationary: bool = false,
    power: PowerUp = .none,
    food: i32 = 0,
    age: i32 = 0,
};

pub const Effect = struct {
    body: Body = .{},
    id: i32 = 0,
    element: Element = .none,
    dir: i32 = 1,
    age: i32 = 0,
    life: i32 = 0,
    spread: bool = false,
};

pub const ParticleText = union(enum) { none, points: i32, one_up };

pub const Particle = struct {
    body: Body = .{},
    text: ParticleText = .none,
    life: i32 = 45,
};

pub const Counters = struct {
    blown: i32 = 0,
    popped: i32 = 0,
    jumps: i32 = 0,
    water: i32 = 0,
    thunder: i32 = 0,
    fire: i32 = 0,
    pink: i32 = 0,
    blue: i32 = 0,
    yellow: i32 = 0,
    walked: Fx = 0,
    water_stage: i32 = 0,
    pending: [16]PowerUp = [_]PowerUp{.none} ** 16,
    pending_count: u8 = 0,

    fn pendingPush(self: *Counters, p: PowerUp) void {
        if (self.pending_count < self.pending.len) {
            self.pending[self.pending_count] = p;
            self.pending_count += 1;
        }
    }
};

pub const Spawn = struct { kind: EnemyKind, col: i32, row: i32 };

pub const Level = struct {
    number: u8 = 1,
    tiles: [@intCast(ROWS)][@intCast(COLUMNS)]u8 = [_][@intCast(COLUMNS)]u8{[_]u8{0} ** @intCast(COLUMNS)} ** @intCast(ROWS),
    enemies: [32]Spawn = [_]Spawn{.{ .kind = .zenchan, .col = 0, .row = 0 }} ** 32,
    enemy_count: u8 = 0,
    player: Cell = .{ .col = 4, .row = 25 },
    food: Cell = .{ .col = 5, .row = 11 },
    power: Cell = .{ .col = 10, .row = 10 },
    special: Element = .none,
    special_count: i32 = 0,

    pub fn solid(self: *const Level, col: i32, row: i32) bool {
        if (col < 2 or col >= COLUMNS - 2) return true;
        if (row < 0 or row >= ROWS) return false;
        return self.tiles[@intCast(row)][@intCast(col)] != 0;
    }
};

pub const Input = struct { move: i32 = 0, jump: bool = false, fire: bool = false };

const MAX_ENEMIES = 16;
const MAX_BUBBLES = 48;
const MAX_PROJECTILES = 16;
const MAX_ITEMS = 16;
const MAX_EFFECTS = 64;
const MAX_PARTICLES = 32;

pub const Rng = struct {
    s: u64,

    pub fn init(seed: u64) Rng {
        return .{ .s = seed ^ 0x9e3779b97f4a7c15 };
    }
    pub fn next(self: *Rng) u32 {
        self.s +%= 0x9e3779b97f4a7c15;
        var z = self.s;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        return @truncate(z ^ (z >> 31));
    }
    pub fn intN(self: *Rng, n: u32) u32 {
        return self.next() % n;
    }
};

pub const Game = struct {
    level: Level = .{},
    level_index: i32 = 0,
    custom: bool = false,
    state: State = .ready,
    paused: bool = false,
    tick: i32 = 0,
    level_ticks: i32 = 0,
    countdown: i32 = 0,
    freeze: i32 = 0,
    hurry: bool = false,
    score: i32 = 0,
    players: [2]Player = .{ .{}, .{} },
    player_count: u8 = 1,
    enemies: [MAX_ENEMIES]Enemy = [_]Enemy{.{}} ** MAX_ENEMIES,
    enemy_count: u8 = 0,
    bubbles: [MAX_BUBBLES]Bubble = [_]Bubble{.{}} ** MAX_BUBBLES,
    bubble_count: u8 = 0,
    projectiles: [MAX_PROJECTILES]Projectile = [_]Projectile{.{}} ** MAX_PROJECTILES,
    projectile_count: u8 = 0,
    items: [MAX_ITEMS]Item = [_]Item{.{}} ** MAX_ITEMS,
    item_count: u8 = 0,
    effects: [MAX_EFFECTS]Effect = [_]Effect{.{}} ** MAX_EFFECTS,
    effect_count: u8 = 0,
    particles: [MAX_PARTICLES]Particle = [_]Particle{.{}} ** MAX_PARTICLES,
    particle_count: u8 = 0,
    sounds: [8]Sound = [_]Sound{.shoot} ** 8,
    sound_count: u8 = 0,
    counters: Counters = .{},
    spawned_special: i32 = 0,
    next_id: i32 = 0,
    extra_life_at: i32 = 30000,
    rng: Rng = .{ .s = 1 },

    // --- setup ------------------------------------------------------------
    pub fn reset(self: *Game, seed: u64, player_count: u8) void {
        self.* = .{};
        self.rng = Rng.init(seed);
        self.player_count = player_count;
        self.extra_life_at = 30000;
        for (&self.players) |*p| p.lives = 3;
        self.loadLevel(0);
    }

    pub fn remainingEnemies(self: *const Game) i32 {
        var n: i32 = 0;
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.state != .defeated) n += 1;
        }
        return n;
    }

    fn anyoneAlive(self: *const Game) bool {
        for (self.players[0..self.player_count]) |p| {
            if (p.alive()) return true;
        }
        return false;
    }

    fn pushSound(self: *Game, s: Sound) void {
        if (self.sound_count >= self.sounds.len) return;
        self.sounds[self.sound_count] = s;
        self.sound_count += 1;
    }

    fn enemy(self: *Game, id: i32) ?*Enemy {
        for (self.enemies[0..self.enemy_count]) |*e| {
            if (e.id == id) return e;
        }
        return null;
    }

    // --- level loading ----------------------------------------------------
    pub fn loadLevel(self: *Game, index: i32) void {
        if (index >= assets.LEVELS.len) {
            self.state = .won;
            return;
        }
        self.level_index = index;
        self.custom = false;
        self.enterLevel(loadLevelData(@intCast(index)));
    }

    /// Play a level that is not the campaign's (the editor's play test).
    pub fn startCustom(self: *Game, level: Level) void {
        self.custom = true;
        self.enterLevel(level);
    }

    fn enterLevel(self: *Game, L: Level) void {
        self.level = L;
        self.level_ticks = 0;
        self.freeze = 0;
        self.spawned_special = 0;
        self.hurry = false;
        self.paused = false;
        self.bubble_count = 0;
        self.projectile_count = 0;
        self.item_count = 0;
        self.effect_count = 0;
        self.particle_count = 0;
        self.enemy_count = 0;
        for (self.level.enemies[0..self.level.enemy_count]) |sp| {
            const pos = spawnPosition(self, .{ .col = sp.col, .row = sp.row });
            self.next_id += 1;
            var dir: i32 = -1;
            if (self.rng.intN(2) == 0) dir = 1;
            self.enemies[self.enemy_count] = .{
                .body = .{ .x = pos.x, .y = pos.y },
                .id = self.next_id,
                .kind = sp.kind,
                .dir = dir,
                .vertical = 1,
                .cooldown = 180,
                .phase = self.rng.next(),
            };
            self.enemy_count += 1;
        }
        var i: u8 = 0;
        while (i < self.player_count) : (i += 1) {
            self.respawn(i);
            self.players[i].invincible = 0;
        }
        self.state = .ready;
        self.countdown = TPS;
    }

    fn respawn(self: *Game, index: u8) void {        var cell = self.level.player;
        if (index == 1) cell.col = COLUMNS - 4 - cell.col;
        const pos = spawnPosition(self, cell);
        const lives = self.players[index].lives;
        self.players[index] = .{
            .body = .{ .x = pos.x, .y = pos.y },
            .lives = lives,
            .dir = 1 - @as(i32, index) * 2,
            .invincible = 210,
        };
    }

    // --- step -------------------------------------------------------------
    pub fn step(self: *Game, in: Input) void {
        var inputs = [_]Input{ in, .{} };
        self.stepPlayers(inputs[0..self.player_count]);
    }

    pub fn stepPlayers(self: *Game, inputs: []const Input) void {
        self.sound_count = 0;
        if (self.paused or self.state == .game_over or self.state == .won) return;
        self.tick += 1;
        if (self.state == .ready) {
            self.countdown -= 1;
            if (self.countdown <= 0) self.state = .playing;
            return;
        }
        var i: u8 = 0;
        while (i < self.player_count) : (i += 1) {
            const p = &self.players[i];
            if (p.dead > 0) {
                p.dead -= 1;
                if (p.dead == 0 and p.lives > 0) {
                    self.respawn(i);
                    self.projectile_count = 0;
                }
            } else if (p.lives > 0) {
                const in = if (i < inputs.len) inputs[i] else Input{};
                self.updatePlayer(i, in);
            }
        }
        var finished = true;
        for (self.players[0..self.player_count]) |p| {
            if (p.lives > 0 or p.dead > 0) finished = false;
        }
        if (finished) {
            self.state = .game_over;
            return;
        }

        if (self.state == .playing) {
            if (self.freeze > 0) {
                self.freeze -= 1;
            } else {
                self.level_ticks += 1;
                if (self.level_ticks >= 30 * TPS and !self.hurry) {
                    self.hurry = true;
                    for (self.enemies[0..self.enemy_count]) |*e| e.angry = true;
                }
                self.updateEnemies();
                self.updateProjectiles();
            }
            self.spawnSpecial();
        }
        self.updateBubbles(inputs);
        self.updateEffects();
        if (self.updateItems()) return;
        self.updateDefeated();
        self.updateParticles();
        if (self.state == .playing) {
            self.checkPowerSpawns();
            i = 0;
            while (i < self.player_count) : (i += 1) self.checkPlayerHit(i);
            if (self.remainingEnemies() == 0 and self.anyoneAlive()) {
                self.state = .clearing;
                self.countdown = 7 * TPS;
                self.projectile_count = 0;
            }
        } else if (self.state == .clearing) {
            self.countdown -= 1;
            if (self.countdown == 0) self.loadLevel(self.level_index + 1);
        }
    }

    // --- player -----------------------------------------------------------
    fn updatePlayer(self: *Game, index: u8, in: Input) void {
        const p = &self.players[index];
        if (p.invincible > 0) p.invincible -= 1;
        if (p.shoot > 0) p.shoot -= 1;
        if (p.cooldown > 0) p.cooldown -= 1;
        if (in.jump and !p.last_jump) p.jump_buffer = 8;
        p.last_jump = in.jump;
        if (p.jump_buffer > 0) p.jump_buffer -= 1;
        if (p.body.ground) {
            p.coyote = 6;
        } else if (p.coyote > 0) {
            p.coyote -= 1;
        }
        if (p.jump_buffer > 0 and p.coyote > 0) {
            p.body.vy = fx(-11.5);
            p.body.ground = false;
            p.coyote = 0;
            p.jump_buffer = 0;
            self.counters.jumps += 1;
            if (p.power.amethyst) self.addScore(500, p.body.x, p.body.y);
            self.pushSound(.jump);
        }
        var speed: Fx = fx(3.0);
        if (p.power.shoes) speed = fx(5.0);
        const move = maxI(-1, minI(1, in.move));
        if (move != 0) {
            p.dir = move;
            p.walk_frame += 1;
        }
        const old_x = p.body.x;
        const dx: Fx = if (move < 0) -speed else if (move > 0) speed else 0;
        self.moveActor(&p.body, dx, true);
        const distance = absFx(p.body.x - old_x);
        self.counters.walked += distance;
        if (p.power.crystal) {
            p.power.walk_points += distance;
            while (p.power.walk_points >= (8 << 16)) {
                self.addScore(10, p.body.x, p.body.y);
                p.power.walk_points -= 8 << 16;
            }
        }
        if (in.fire and p.cooldown == 0) {
            self.shootBubble(index);
            p.cooldown = 18;
            if (p.power.yellow) p.cooldown = 5;
            p.shoot = 12;
        }
    }

    fn checkPlayerHit(self: *Game, index: u8) void {
        const p = &self.players[index];
        if (p.invincible > 0 or !p.alive()) return;
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.state == .active and intersects(p.body.x + (5 << 16), p.body.y + (5 << 16), 34, 36, e.body.x + (4 << 16), e.body.y + (4 << 16), 36, 36)) {
                self.hurtPlayer(index);
                return;
            }
        }
        for (self.projectiles[0..self.projectile_count]) |*b| {
            if (!b.removed and intersects(p.body.x + (5 << 16), p.body.y + (5 << 16), 34, 36, b.body.x, b.body.y, 16, 20)) {
                b.removed = true;
                self.hurtPlayer(index);
                return;
            }
        }
    }

    fn hurtPlayer(self: *Game, index: u8) void {
        const p = &self.players[index];
        if (!p.alive() or p.invincible > 0) return;
        p.lives -= 1;
        p.dead = 90;
        p.power = .{};
        self.pushSound(.death);
    }

    fn updateParticles(self: *Game) void {
        var kept: u8 = 0;
        var i: u8 = 0;
        while (i < self.particle_count) : (i += 1) {
            var p = self.particles[i];
            p.life -= 1;
            p.body.y -= fx(0.6);
            if (p.life > 0) {
                self.particles[kept] = p;
                kept += 1;
            }
        }
        self.particle_count = kept;
    }

    fn defeat(self: *Game, e: *Enemy, multiplier: i32) void {
        if (e.state == .defeated) return;
        e.state = .defeated;
        e.dead_ticks = 50;
        e.body.vx = @as(Fx, direction(e.body.x - @as(Fx, (WIDTH / 2) << 16))) * fx(4.0);
        e.body.vy = fx(-8.0);
        self.addScore(100 * multiplier, e.body.x, e.body.y);
    }

    fn addScore(self: *Game, points: i32, x: Fx, y: Fx) void {
        self.score += points;
        if (points >= 100 and self.particle_count < MAX_PARTICLES) {
            self.particles[self.particle_count] = .{ .body = .{ .x = x, .y = y }, .text = .{ .points = points }, .life = 45 };
            self.particle_count += 1;
        }
        while (self.score >= self.extra_life_at) {
            var i: u8 = 0;
            while (i < self.player_count) : (i += 1) {
                const p = &self.players[i];
                p.lives += 1;
                if (p.lives == 1 and p.dead == 0) self.respawn(i);
            }
            self.extra_life_at += 100000;
            if (self.particle_count < MAX_PARTICLES) {
                self.particles[self.particle_count] = .{
                    .body = .{ .x = self.players[0].body.x, .y = self.players[0].body.y - (24 << 16) },
                    .text = .one_up,
                    .life = 90,
                };
                self.particle_count += 1;
            }
        }
    }

    // --- physics ----------------------------------------------------------
    fn blocked(self: *const Game, x: Fx, y: Fx, size: i32) bool {
        const r0 = @divFloor(y, @as(Fx, TILE << 16));
        const r1 = @divFloor(y + @as(Fx, size << 16) - 655, @as(Fx, TILE << 16));
        const c0 = @divFloor(x, @as(Fx, TILE << 16));
        const c1 = @divFloor(x + @as(Fx, size << 16) - 655, @as(Fx, TILE << 16));
        var row = r0;
        while (row <= r1) : (row += 1) {
            var col = c0;
            while (col <= c1) : (col += 1) {
                if (self.level.solid(col, row)) return true;
            }
        }
        return false;
    }

    fn spawnPosition(self: *const Game, cell: Cell) Point {
        const p = cellPosition(cell, ACTOR);
        if (!self.blocked(p.x, p.y, ACTOR)) return p;
        var best: i64 = std.math.maxInt(i64);
        var best_x = p.x;
        var best_y = p.y;
        var row: i32 = 1;
        while (row < ROWS - 2) : (row += 1) {
            var col: i32 = 2;
            while (col < COLUMNS - 3) : (col += 1) {
                const xx: Fx = col * TILE << 16;
                const yy: Fx = row * TILE << 16;
                const distance: i64 = @as(i64, absFx(xx - p.x)) + @as(i64, absFx(yy - p.y));
                if (distance < best and !self.blocked(xx, yy, ACTOR)) {
                    best = distance;
                    best_x = xx;
                    best_y = yy;
                }
            }
        }
        return .{ .x = best_x, .y = best_y };
    }

    /// Platforms are one-way while rising. Steps avoid tunnelling.
    fn moveActor(self: *const Game, b: *Body, dx: Fx, gravity: bool) void {
        const inside = self.blocked(b.x + (2 << 16), b.y + (2 << 16), ACTOR - 4);
        const steps = maxI(1, ceilPx(absFx(dx)));
        var i: i32 = 0;
        while (i < steps) : (i += 1) {
            const nx = clamp(b.x + @divTrunc(dx, steps), 2 * TILE << 16, @as(Fx, (WIDTH - 2 * TILE - ACTOR) << 16));
            if (b.vy >= 0 and !inside and self.blocked(nx + (2 << 16), b.y + (2 << 16), ACTOR - 4)) break;
            b.x = nx;
        }
        if (gravity) b.vy = minFx(fx(12.0), b.vy + fx(0.5));
        const old_feet = b.y + (ACTOR << 16);
        var new_y = b.y + b.vy;
        b.ground = false;
        if (b.vy >= 0) {
            const first = @divFloor(old_feet + @as(Fx, (TILE << 16) - 1), @as(Fx, TILE << 16));
            const last = @divFloor(new_y + @as(Fx, ACTOR << 16), @as(Fx, TILE << 16));
            var row = first;
            outer: while (row <= last) : (row += 1) {
                var col = @divTrunc(b.x + (4 << 16), @as(Fx, TILE << 16));
                const lastc = @divTrunc(b.x + @as(Fx, (ACTOR - 4) << 16), @as(Fx, TILE << 16));
                while (col <= lastc) : (col += 1) {
                    if (self.level.solid(col, row)) {
                        new_y = @as(Fx, row * TILE - ACTOR) << 16;
                        b.vy = 0;
                        b.ground = true;
                        break :outer;
                    }
                }
            }
        }
        b.y = new_y;
        if (b.y < (TILE << 16)) {
            b.y = TILE << 16;
            b.vy = maxFx(0, b.vy);
        }
        if (b.y > (HEIGHT << 16)) {
            b.y = TILE << 16;
            b.vy = fx(2.0);
        }
    }

    fn moveFlying(self: *const Game, e: *Enemy, dx: Fx, dy: Fx) void {
        const steps = maxI(1, @max(ceilPx(absFx(dx)), ceilPx(absFx(dy))));
        var i: i32 = 0;
        while (i < steps) : (i += 1) {
            const x = e.body.x + @divTrunc(dx, steps);
            if (self.blocked(x + (3 << 16), e.body.y + (3 << 16), ACTOR - 6)) {
                e.dir = -e.dir;
                break;
            }
            e.body.x = x;
        }
        i = 0;
        while (i < steps) : (i += 1) {
            const y = e.body.y + @divTrunc(dy, steps);
            if (y < (TILE << 16) or y > @as(Fx, (HEIGHT - ACTOR) << 16) or self.blocked(e.body.x + (3 << 16), y + (3 << 16), ACTOR - 6)) {
                e.vertical = -e.vertical;
                break;
            }
            e.body.y = y;
        }
    }

    // --- enemies ----------------------------------------------------------
    fn target(self: *const Game, body: Body) Player {
        var best: i64 = std.math.maxInt(i64);
        var t = self.players[0];
        for (self.players[0..self.player_count]) |p| {
            const distance: i64 = @as(i64, absFx(p.body.x - body.x)) + @as(i64, absFx(p.body.y - body.y));
            if (p.alive() and distance < best) {
                best = distance;
                t = p;
            }
        }
        return t;
    }

    fn updateEnemies(self: *Game) void {
        for (self.enemies[0..self.enemy_count]) |*e| {
            const t = self.target(e.body);
            e.age += 1;
            if (e.state == .trapped or e.state == .carried) continue;
            if (e.state == .defeated) continue;
            if (e.cooldown > 0) e.cooldown -= 1;
            if (e.shoot > 0) {
                e.shoot -= 1;
                continue;
            }
            var speed: Fx = fx(2.5);
            if (e.angry) speed = fx(3.5);
            switch (e.kind) {
                .monsta => self.moveFlying(e, @as(Fx, e.dir) * speed, @as(Fx, e.vertical) * speed),
                .pulpul => {
                    // The Go: dir*(1.4+|sin(phase)|*speed), vertical*(0.7+|cos(2*phase)|*speed)
                    e.phase +%= 23924784; // 0.035 rad as a one-turn u32 angle
                    const s = trig.sin(e.phase);
                    const c = trig.cos(e.phase << 1);
                    const sx: Fx = if (s < 0) -s else s;
                    const cx: Fx = if (c < 0) -c else c;
                    const dx = fx(1.4) + mul(sx, speed);
                    const dy = fx(0.7) + mul(cx, speed);
                    self.moveFlying(e, if (e.dir < 0) -dx else dx, if (e.vertical < 0) -dy else dy);
                },
                else => {
                    if (e.kind == .invader) speed = mul(speed, fx(1.5));
                    if (e.body.ground) {
                        switch (e.kind) {
                            .banebou => e.body.vy = if (e.angry) fx(-10.0) else fx(-7.5),
                            .zenchan, .mighta => {
                                if (e.cooldown == 0 and t.body.y < e.body.y - (TILE << 16)) {
                                    e.body.vy = fx(-11.5);
                                    e.dir = direction(t.body.x - e.body.x);
                                    e.cooldown = 60;
                                }
                            },
                            else => {},
                        }
                    }
                    if (e.kind == .mighta and e.cooldown == 0 and absFx(e.body.y - t.body.y) < (TILE << 16) and t.alive()) {
                        e.dir = direction(t.body.x - e.body.x);
                        self.addProjectile(.{
                            .body = .{ .x = e.body.x + (20 << 16) + @as(Fx, e.dir) * (24 << 16), .y = e.body.y + (14 << 16), .vx = @as(Fx, e.dir) * fx(6.0) },
                        });
                        e.cooldown = 180;
                        e.shoot = 30;
                    }
                    if (e.kind == .invader and e.cooldown == 0) {
                        self.addProjectile(.{
                            .body = .{ .x = e.body.x + (16 << 16), .y = e.body.y + (ACTOR << 16), .vy = fx(6.0) },
                            .laser = true,
                        });
                        e.cooldown = 180;
                        e.shoot = 12;
                        self.pushSound(.laser);
                    }
                    const old_x = e.body.x;
                    self.moveActor(&e.body, @as(Fx, e.dir) * speed, true);
                    if (absFx(e.body.x - old_x) < 655) e.dir = -e.dir;
                },
            }
        }
    }

    fn addProjectile(self: *Game, p: Projectile) void {
        if (self.projectile_count >= MAX_PROJECTILES) return;
        self.projectiles[self.projectile_count] = p;
        self.projectile_count += 1;
    }

    fn updateDefeated(self: *Game) void {
        for (self.enemies[0..self.enemy_count]) |*e| {
            if (e.state == .defeated and e.dead_ticks > 0) {
                e.dead_ticks -= 1;
                e.body.x += e.body.vx;
                e.body.y += e.body.vy;
                e.body.vy += fx(0.45);
                if (e.dead_ticks == 0) self.spawnFood(e.body.x, e.body.y);
            }
        }
    }

    fn updateProjectiles(self: *Game) void {
        var kept: u8 = 0;
        var i: u8 = 0;
        while (i < self.projectile_count) : (i += 1) {
            var p = self.projectiles[i];
            p.age += 1;
            const steps = maxI(1, @max(ceilPx(absFx(p.body.vx)), ceilPx(absFx(p.body.vy))));
            var s: i32 = 0;
            while (s < steps) : (s += 1) {
                p.body.x += @divTrunc(p.body.vx, steps);
                p.body.y += @divTrunc(p.body.vy, steps);
                if (self.blocked(p.body.x, p.body.y, 16) or p.body.y > (HEIGHT << 16)) {
                    p.removed = true;
                    break;
                }
            }
            if (!p.removed and p.age < 5 * TPS) {
                self.projectiles[kept] = p;
                kept += 1;
            }
        }
        self.projectile_count = kept;
    }

    // --- bubbles ----------------------------------------------------------
    const BUBBLE_SIZE: i32 = 40;

    fn shootBubble(self: *Game, player: u8) void {
        const p = &self.players[player];
        var speed: i32 = 8;
        var reach: i32 = 200;
        if (p.power.blue) speed = 16;
        if (p.power.pink) reach = 400;
        self.next_id += 1;
        if (self.bubble_count < MAX_BUBBLES) {
            self.bubbles[self.bubble_count] = .{
                .body = .{ .x = p.body.x + @as(Fx, p.dir) * (18 << 16), .y = p.body.y + (2 << 16) },
                .id = self.next_id,
                .dir = p.dir,
                .speed = speed,
                .max_distance = reach,
            };
            self.bubble_count += 1;
        }
        self.counters.blown += 1;
        if (p.power.ruby) self.addScore(100, p.body.x, p.body.y);
        self.pushSound(.shoot);
    }

    /// Harness hooks: pop a bubble exactly as touching one does, and hand the
    /// player a power-up as collecting one does.
    pub fn bubblePopForTest(self: *Game, index: u8) void {
        self.popBubble(index, 0);
    }
    pub fn testApplyPower(self: *Game, p: PowerUp) bool {
        return self.applyPower(p, 0);
    }

    fn updateBubbles(self: *Game, inputs: []const Input) void {
        var i: u8 = 0;
        while (i < self.bubble_count) : (i += 1) {
            const b = &self.bubbles[i];
            if (b.removed) continue;
            b.age += 1;
            if (b.element != .none) {
                self.moveSpecialBubble(b);
            } else if (!b.floating) {
                var k: i32 = 0;
                while (k < b.speed) : (k += 1) {
                    b.body.x += @as(Fx, b.dir) << 16;
                    b.distance += 1;
                    for (self.enemies[0..self.enemy_count]) |*e| {
                        if (e.state == .active and intersects(b.body.x, b.body.y, BUBBLE_SIZE, BUBBLE_SIZE, e.body.x + (3 << 16), e.body.y + (3 << 16), 38, 38)) {
                            b.enemy_id = e.id;
                            e.state = .trapped;
                            b.floating = true;
                            break;
                        }
                    }
                    if (b.floating or b.distance >= b.max_distance or self.blocked(b.body.x + (4 << 16), b.body.y + (4 << 16), BUBBLE_SIZE - 8)) {
                        b.floating = true;
                        break;
                    }
                }
            } else {
                var ceiling: i32 = 2 * TILE;
                if (self.level.number == 24) ceiling = 9 * TILE;
                if (b.body.y > (ceiling << 16)) {
                    b.body.y -= fx(1.15);
                } else {
                    b.body.y = (ceiling << 16) + mul(trig.sin(@as(u32, @intCast(b.age)) *% 24413045), fx(4.0));
                }
                b.body.x += mul(trig.sin((@as(u32, @intCast(b.id)) *% 1162060967) +% (@as(u32, @intCast(b.age)) *% 11392754)), fx(0.2));
            }
            b.body.x = clamp(b.body.x, 2 * TILE << 16, @as(Fx, (WIDTH - 2 * TILE - BUBBLE_SIZE) << 16));
            if (b.enemy_id != 0) {
                b.captured_age += 1;
                if (self.enemy(b.enemy_id)) |e| {
                    e.body.x = b.body.x;
                    e.body.y = b.body.y;
                }
                if (b.captured_age > 1270) {
                    if (self.enemy(b.enemy_id)) |e| {
                        e.state = .active;
                        e.angry = true;
                        e.body.vy = 0;
                        e.body.y += 4 << 16;
                    }
                    b.removed = true;
                    continue;
                }
            } else if (b.age > 600) {
                b.removed = true;
                continue;
            }
            var player: u8 = 0;
            while (player < self.player_count) : (player += 1) {
                const in = if (player < inputs.len) inputs[player] else Input{};
                const p = &self.players[player];
                if (!p.alive() or b.age <= 20 or b.removed) continue;
                if (in.jump and p.body.vy >= 0 and p.body.y + (ACTOR << 16) >= b.body.y and
                    p.body.y + @as(Fx, ACTOR << 16) - p.body.vy <= b.body.y + (10 << 16) and
                    p.body.x + (ACTOR << 16) > b.body.x + (4 << 16) and p.body.x < b.body.x + @as(Fx, (BUBBLE_SIZE - 4) << 16))
                {
                    p.body.y = b.body.y - (ACTOR << 16);
                    p.body.vy = fx(-10.5);
                    p.body.ground = false;
                    self.pushSound(.jump);
                    continue;
                }
                if (intersects(p.body.x + (4 << 16), p.body.y + (4 << 16), 36, 36, b.body.x, b.body.y, BUBBLE_SIZE, BUBBLE_SIZE)) {
                    self.popBubble(i, player);
                }
            }
        }
        var kept: u8 = 0;
        i = 0;
        while (i < self.bubble_count) : (i += 1) {
            if (!self.bubbles[i].removed) {
                self.bubbles[kept] = self.bubbles[i];
                kept += 1;
            }
        }
        self.bubble_count = kept;
    }

    fn popBubble(self: *Game, index: u8, player: u8) void {
        var queue: [MAX_BUBBLES + 4]u8 = [_]u8{0} ** (MAX_BUBBLES + 4);
        var qn: u8 = 0;
        var qh: u8 = 0;
        queue[qn] = index;
        qn += 1;
        var combo: i32 = 0;
        while (qh < qn) {
            const i = queue[qh];
            qh += 1;
            const b = &self.bubbles[i];
            if (b.removed) continue;
            b.removed = true;
            self.counters.popped += 1;
            if (self.particle_count < MAX_PARTICLES) {
                self.particles[self.particle_count] = .{ .body = .{ .x = b.body.x, .y = b.body.y }, .text = .none, .life = 15 };
                self.particle_count += 1;
            }
            if (self.enemy(b.enemy_id)) |e| {
                if (e.state == .trapped) {
                    combo += 1;
                    self.defeat(e, @as(i32, 1) << @as(u5, @intCast(@min(combo - 1, 5))));
                    const pos = cellPosition(self.level.food, 32);
                    if (self.item_count < MAX_ITEMS) {
                        self.items[self.item_count] = .{ .body = .{ .x = pos.x, .y = pos.y }, .food = self.level.number, .stationary = true };
                        self.item_count += 1;
                    }
                }
            }
            if (b.element != .none) self.releaseElement(b, player);
            var j: u8 = 0;
            while (j < self.bubble_count) : (j += 1) {
                const other = &self.bubbles[j];
                if (!other.removed and other.age > 20 and
                    intersects(b.body.x - (6 << 16), b.body.y - (6 << 16), BUBBLE_SIZE + 12, BUBBLE_SIZE + 12, other.body.x, other.body.y, BUBBLE_SIZE, BUBBLE_SIZE))
                {
                    if (qn < queue.len) {
                        queue[qn] = j;
                        qn += 1;
                    }
                }
            }
        }
        self.pushSound(.pop);
    }

    fn spawnSpecial(self: *Game) void {
        if (self.level.special == .none or self.spawned_special >= self.level.special_count) return;
        if (self.freeze == 0 and self.level_ticks >= 1 and self.spawned_special <= @divTrunc(self.level_ticks - 1, 450)) {
            self.next_id += 1;
            if (self.bubble_count < MAX_BUBBLES) {
                self.bubbles[self.bubble_count] = .{
                    .body = .{ .x = 252 << 16, .y = TILE << 16 },
                    .id = self.next_id,
                    .dir = 1,
                    .age = 21,
                    .floating = true,
                    .element = self.level.special,
                };
                self.bubble_count += 1;
            }
            self.spawned_special += 1;
        }
    }

    fn moveSpecialBubble(self: *const Game, b: *Bubble) void {
        if (!self.blocked(b.body.x + (4 << 16), b.body.y + (7 << 16), BUBBLE_SIZE - 8)) {
            b.body.y += fx(3.0);
        } else {
            const next = b.body.x + @as(Fx, b.dir) * fx(2.0);
            if (self.blocked(next + (4 << 16), b.body.y + (4 << 16), BUBBLE_SIZE - 8)) {
                b.dir = -b.dir;
            } else {
                b.body.x = next;
            }
        }
        if (b.body.y > (HEIGHT << 16)) b.body.y = TILE << 16;
    }

    // --- effects ----------------------------------------------------------
    fn releaseElement(self: *Game, b: *Bubble, player: u8) void {
        self.next_id += 1;
        var e = Effect{ .id = self.next_id, .body = .{ .x = b.body.x, .y = b.body.y }, .element = b.element, .dir = self.players[player].dir, .life = 300 };
        switch (b.element) {
            .water => {
                self.counters.water += 1;
                e.life = 420;
                self.pushSound(.water);
            },
            .thunder => {
                self.counters.thunder += 1;
                e.life = 90;
                self.pushSound(.laser);
            },
            .fire => {
                self.counters.fire += 1;
                self.pushSound(.fire);
            },
            else => {},
        }
        self.addEffect(e);
    }

    fn addEffect(self: *Game, e: Effect) void {
        if (self.effect_count >= MAX_EFFECTS) return;
        self.effects[self.effect_count] = e;
        self.effect_count += 1;
    }

    fn updateEffects(self: *Game) void {
        var spawned: [MAX_EFFECTS]Effect = undefined;
        var spawned_n: u8 = 0;
        const size: i32 = 32;
        for (self.effects[0..self.effect_count]) |*e| {
            e.age += 1;
            e.life -= 1;
            switch (e.element) {
                .thunder => {
                    var k: i32 = 0;
                    while (k < 12) : (k += 1) {
                        e.body.x += @as(Fx, e.dir) << 16;
                        self.hitWithElement(e, 40, 24);
                    }
                    if (e.body.x < (2 * TILE << 16) or e.body.x > @as(Fx, (WIDTH - 2 * TILE) << 16)) e.life = 0;
                },
                .water => {
                    if (!self.blocked(e.body.x + (3 << 16), e.body.y + (6 << 16), size - 6)) {
                        e.body.y += fx(3.0);
                    } else {
                        const next = e.body.x + @as(Fx, e.dir) * fx(3.0);
                        if (self.blocked(next + (3 << 16), e.body.y + (3 << 16), size - 6)) {
                            e.dir = -e.dir;
                        } else {
                            e.body.x = next;
                        }
                    }
                    if (@mod(e.age, 12) == 0 and e.age <= 72 and !e.spread and spawned_n < spawned.len) {
                        spawned[spawned_n] = .{ .body = e.body, .element = .water, .dir = e.dir, .life = 150, .spread = true };
                        spawned_n += 1;
                    }
                    if (e.body.y > (HEIGHT << 16)) e.life = 0;
                    self.hitWithElement(e, size, size);
                    self.carryOnWater(e);
                },
                .fire => {
                    if (!e.body.ground) {
                        if (!self.blocked(e.body.x + (3 << 16), e.body.y + (7 << 16), size - 6)) {
                            e.body.y += fx(4.0);
                        } else {
                            e.body.ground = true;
                            if (!e.spread) {
                                for ([_]i32{ -1, 1 }) |d| {
                                    if (spawned_n < spawned.len) {
                                        spawned[spawned_n] = .{
                                            .body = .{ .x = e.body.x + @as(Fx, d) * (28 << 16), .y = e.body.y },
                                            .element = .fire,
                                            .dir = d,
                                            .life = 300,
                                            .spread = true,
                                        };
                                        spawned_n += 1;
                                    }
                                }
                            }
                        }
                    }
                    if (e.body.y > (HEIGHT << 16)) e.life = 0;
                    self.hitWithElement(e, size, size);
                },
                else => {},
            }
        }
        var kept: u8 = 0;
        var i: u8 = 0;
        while (i < self.effect_count) : (i += 1) {
            if (self.effects[i].life > 0) {
                self.effects[kept] = self.effects[i];
                kept += 1;
            }
        }
        i = 0;
        while (i < spawned_n) : (i += 1) {
            if (kept >= MAX_EFFECTS) break;
            self.effects[kept] = spawned[i];
            kept += 1;
        }
        self.effect_count = kept;
    }

    fn hitWithElement(self: *Game, effect: *Effect, w: i32, h: i32) void {
        if (effect.element == .fire and !effect.body.ground) return;
        for (self.enemies[0..self.enemy_count]) |*e| {
            if (e.state == .active and intersects(effect.body.x, effect.body.y, w, h, e.body.x, e.body.y, ACTOR, ACTOR)) {
                if (effect.element == .water and !effect.spread) {
                    e.state = .carried;
                    e.carried_by = effect.id;
                    e.carry_ticks = 0;
                } else if (effect.element != .water) {
                    self.defeat(e, 2);
                }
            }
        }
    }

    fn carryOnWater(self: *Game, effect: *Effect) void {
        if (effect.spread) return;
        for (self.enemies[0..self.enemy_count]) |*e| {
            if (e.state == .carried and e.carried_by == effect.id) {
                e.body.x = effect.body.x;
                e.body.y = effect.body.y - (12 << 16);
                e.carry_ticks += 1;
                if (effect.life <= 0 or e.carry_ticks >= 3 * TPS or e.body.y > @as(Fx, (HEIGHT - ACTOR) << 16)) {
                    self.defeat(e, 2);
                }
            }
        }
        var i: u8 = 0;
        while (i < self.player_count) : (i += 1) {
            const p = &self.players[i];
            if (p.alive() and p.body.vy >= 0 and intersects(p.body.x, p.body.y, ACTOR, ACTOR, effect.body.x, effect.body.y, 32, 32)) {
                const x = effect.body.x;
                const y = effect.body.y - (12 << 16);
                if (!self.blocked(x, y, ACTOR)) {
                    p.body.x = x;
                    p.body.y = y;
                }
            }
        }
    }

    // --- items ------------------------------------------------------------
    pub fn foodScore(level: i32) i32 {
        if (level <= 10) return @max(1, level) * 10;
        return 100 + (minI(level, 25) - 10) * 50;
    }

    fn spawnFood(self: *Game, x: Fx, y: Fx) void {
        const cx = clamp(x, 2 * TILE << 16, @as(Fx, (WIDTH - 2 * TILE - 32) << 16));
        const cy = clamp(y, TILE << 16, @as(Fx, (HEIGHT - 2 * TILE) << 16));
        if (self.item_count >= MAX_ITEMS) return;
        self.items[self.item_count] = .{ .body = .{ .x = cx, .y = cy }, .food = self.level.number };
        self.item_count += 1;
    }

    fn checkPowerSpawns(self: *Game) void {
        const c = &self.counters;
        const rules = [_]struct { count: *i32, threshold: i32, power: PowerUp }{
            .{ .count = &c.blown, .threshold = 35, .power = .pink_candy },
            .{ .count = &c.popped, .threshold = 35, .power = .blue_candy },
            .{ .count = &c.jumps, .threshold = 35, .power = .yellow_candy },
            .{ .count = &c.thunder, .threshold = 12, .power = .clock },
            .{ .count = &c.fire, .threshold = 13, .power = .dynamite },
            .{ .count = &c.blue, .threshold = 3, .power = .crystal_ring },
            .{ .count = &c.yellow, .threshold = 3, .power = .amethyst_ring },
            .{ .count = &c.pink, .threshold = 3, .power = .ruby_ring },
        };
        for (rules) |r| {
            while (r.count.* >= r.threshold) {
                r.count.* -= r.threshold;
                c.pendingPush(r.power);
            }
        }
        if (c.walked >= WIDTH * 15 << 16) {
            c.walked -= WIDTH * 15 << 16;
            c.pendingPush(.shoes);
        }
        if (c.water >= 15 and c.water_stage == 0) {
            c.pendingPush(.orange_parasol);
            c.water_stage = 1;
        }
        if (c.water >= 20 and c.water_stage == 1) {
            c.pendingPush(.red_parasol);
            c.water_stage = 2;
        }
        if (c.water >= 25 and c.water_stage == 2) {
            c.pendingPush(.purple_parasol);
            c.water -= 25;
            c.water_stage = 0;
        }
        if (c.pending_count == 0) return;
        for (self.items[0..self.item_count]) |item| {
            if (item.power != .none) return;
        }
        const pos = cellPosition(self.level.power, 32);
        if (self.item_count < MAX_ITEMS) {
            self.items[self.item_count] = .{ .body = .{ .x = pos.x, .y = pos.y }, .power = c.pending[0] };
            self.item_count += 1;
        }
        var i: u8 = 1;
        while (i < c.pending_count) : (i += 1) c.pending[i - 1] = c.pending[i];
        c.pending_count -= 1;
    }

    /// Returns true when the level changed under the player's feet (a warp).
    fn updateItems(self: *Game) bool {
        var kept: u8 = 0;
        var i: u8 = 0;
        while (i < self.item_count) : (i += 1) {
            var item = self.items[i];
            item.age += 1;
            if (item.age > 12 * TPS) continue;
            if (item.power == .none and !item.stationary) {
                const old_feet = item.body.y + (32 << 16);
                item.body.vy = minFx(fx(6.0), item.body.vy + fx(0.3));
                const new_feet = old_feet + item.body.vy;
                var row = @divTrunc(toInt(old_feet), TILE);
                if ((row * TILE << 16) < old_feet) row += 1;
                if ((row * TILE << 16) <= new_feet and (self.level.solid(@divTrunc(toInt(item.body.x), TILE), row) or self.level.solid(@divTrunc(item.body.x + (31 << 16), @as(Fx, TILE << 16)), row))) {
                    item.body.y = @as(Fx, row * TILE - 32) << 16;
                    item.body.vy = 0;
                } else {
                    item.body.y += item.body.vy;
                }
                if (item.body.y > (HEIGHT << 16)) {
                    const pos = cellPosition(self.level.food, 32);
                    item.body.x = pos.x;
                    item.body.y = pos.y;
                    item.body.vy = 0;
                }
            }
            var collected = false;
            var player: u8 = 0;
            while (player < self.player_count) : (player += 1) {
                const p = self.players[player];
                if (!p.alive() or !intersects(p.body.x, p.body.y, ACTOR, ACTOR, item.body.x, item.body.y, 32, 32)) continue;
                if (item.power != .none) {
                    if (self.applyPower(item.power, player)) return true;
                } else {
                    self.addScore(foodScore(item.food), item.body.x, item.body.y);
                    self.pushSound(.food);
                }
                collected = true;
                break;
            }
            if (collected) continue;
            self.items[kept] = item;
            kept += 1;
        }
        self.item_count = kept;
        return false;
    }

    fn applyPower(self: *Game, power: PowerUp, player: u8) bool {
        const p = &self.players[player].power;
        var points: i32 = 100;
        var warp: i32 = 0;
        switch (power) {
            .pink_candy => {
                p.pink = true;
                self.counters.pink += 1;
            },
            .blue_candy => {
                p.blue = true;
                self.counters.blue += 1;
            },
            .yellow_candy => {
                p.yellow = true;
                self.counters.yellow += 1;
            },
            .shoes => p.shoes = true,
            .orange_parasol => {
                points = 200;
                warp = 3;
            },
            .red_parasol => {
                points = 200;
                warp = 5;
            },
            .purple_parasol => {
                points = 200;
                warp = 7;
            },
            .crystal_ring => {
                points = 1000;
                p.crystal = true;
            },
            .amethyst_ring => {
                points = 1000;
                p.amethyst = true;
            },
            .ruby_ring => {
                points = 1000;
                p.ruby = true;
            },
            .dynamite => {
                points = 200;
                for (self.enemies[0..self.enemy_count]) |*e| self.defeat(e, 2);
                for (self.bubbles[0..self.bubble_count]) |*b| {
                    if (b.enemy_id != 0) b.removed = true;
                }
                self.projectile_count = 0;
                self.pushSound(.explosion);
            },
            .clock => {
                points = 200;
                self.freeze = 7 * TPS;
            },
            .none => {},
        }
        self.addScore(points, self.players[player].body.x, self.players[player].body.y);
        self.pushSound(.item);
        if (warp > 0) {
            self.loadLevel(self.level_index + warp);
            return true;
        }
        return false;
    }
};

/// Build a Level from the embedded campaign data (level tiles from levels.bin,
/// spawns from the generated table).
pub fn loadLevelData(index: u8) Level {
    var L = Level{};
    const info = assets.LEVELS[index];
    L.number = info.number;
    L.player = .{ .col = info.player[0], .row = info.player[1] };
    L.food = .{ .col = info.food[0], .row = info.food[1] };
    L.power = .{ .col = info.power[0], .row = info.power[1] };
    L.special = @enumFromInt(info.special);
    L.special_count = info.special_count;
    const base = @as(usize, index) * @as(usize, @intCast(COLUMNS * ROWS));
    var r: usize = 0;
    while (r < @as(usize, @intCast(ROWS))) : (r += 1) {
        var c: usize = 0;
        while (c < @as(usize, @intCast(COLUMNS))) : (c += 1) {
            L.tiles[r][c] = assets.LEVEL_TILES[base + r * @as(usize, @intCast(COLUMNS)) + c];
        }
    }
    const n: usize = @min(@as(usize, info.count), L.enemies.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const s = assets.SPAWNS[@as(usize, info.first) + i];
        L.enemies[i] = .{ .kind = @enumFromInt(s.kind), .col = s.col, .row = s.row };
    }
    L.enemy_count = @intCast(n);
    return L;
}
