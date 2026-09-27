// --------------------------------------------------------------------------
// ZIG mode's tracers. The original's guns draw nothing: 350-359 take a round
// (ammo - 1) and test each enemy's DIRECTION from the plane; a hit is a
// dice roll (390). ZIG shows the burst: every round the game takes, three
// short streaks leave the plane's nose along its heading (r: the listing's
// dx() / dy() table, the same the plane flies by), fast, and vanish at the
// view's edge or on reaching an enemy fighter.
//
// Purely a picture: a round is SEEN (the guns' hook in 350 counts each one
// the game takes, zig_hooks.rounds), never taken, and nothing here is read
// by the game. Not the ammo going down: on a home airfield, stopped, line
// 101 rearms (532) in the same pass as the guns fire, so the count never
// moves there -- which is why no tracer showed on the ground. The colours are the
// palette's own: its most fiery (red + green - blue) for the head, the next
// for the tail, so the streaks read on the sky and on the white clouds.
// --------------------------------------------------------------------------
const pal = @import("pal.zig");
const sprite = @import("sprite.zig");
const ring = @import("zig_ring.zig");
const overlay = @import("zig_overlay.zig");
const scroll = @import("zig_scroll.zig");
const hooks = @import("zig_hooks.zig");
const set = @import("zig_settings.zig");
const V = @import("vars.zig");
const v = &V.v;

const MAX = set.tracer_max;
const PER_ROUND = set.tracer_per_round;
const LIFE = set.tracer_life;
const SPEED = set.tracer_speed;
const LEN = set.tracer_len;
const HEAD = set.tracer_head;
const REACH = set.tracer_reach;

const Streak = struct { x: i32 = 0, y: i32 = 0, dx: i32 = 0, dy: i32 = 0, life: u8 = 0 };

var streaks: [MAX]Streak = [_]Streak{.{}} ** MAX;
var rounds_seen: ?u32 = null;
/// Streaks drawn last frame, and the two indices they used (harness).
pub var shown: u32 = 0;
pub var ink: u8 = 3;
pub var tail: u8 = 11;

pub fn clear() void {
    streaks = [_]Streak{.{}} ** MAX;
    rounds_seen = null;
    shown = 0;
}

/// A round taken since last frame: a burst from the plane's nose.
pub fn watch() void {
    const took = if (rounds_seen) |r| hooks.rounds != r else false;
    rounds_seen = hooks.rounds;
    if (!took or v.bale != 0) return;
    const p = sprite.shown[1];
    if (!p.on) return;
    const r = overlay.quiet(16, v.r);
    const dx = v.dx_a[r];
    const dy = v.dy_a[r][0];
    const x0 = p.fx * ring.SEC + p.x;
    const y0 = -p.fy * ring.LAYER + p.y;
    var k: i32 = 0;
    while (k < PER_ROUND) : (k += 1) spawn(x0 + dx * (2 + 4 * k), y0 + dy * (2 + 4 * k), dx * SPEED, dy * SPEED);
}

fn spawn(x: i32, y: i32, dx: i32, dy: i32) void {
    for (&streaks) |*s| if (s.life == 0) {
        s.* = .{ .x = x, .y = y, .dx = dx, .dy = dy, .life = LIFE };
        return;
    };
}

/// Move, stop, and draw them into the overlay's world part (camera `at`).
pub fn draw(view: []u8, at: [2]i32) void {
    fiery();
    shown = 0;
    for (&streaks) |*s| {
        if (s.life == 0) continue;
        s.life -= 1;
        s.x += s.dx;
        s.y += s.dy;
        const px = ring.wrapDelta(s.x - at[0]);
        const py = s.y - at[1];
        if (px < 0 or px >= scroll.WIN_W or py < 0 or py >= scroll.VIEW_H or struck(s)) {
            s.life = 0;
            continue;
        }
        line(view, px, py, s.dx, s.dy);
        shown += 1;
    }
}

/// Its head at an enemy fighter the game shows.
fn struck(s: *const Streak) bool {
    for (3..5) |n| {
        const e = sprite.shown[n];
        if (!e.on) continue;
        const ex = e.fx * ring.SEC + e.x;
        const ey = -e.fy * ring.LAYER + e.y;
        if (@abs(ring.wrapDelta(ex - s.x)) <= REACH and @abs(ey - s.y) <= REACH) return true;
    }
    return false;
}

/// LEN pixels back from the head along (dx, dy).
fn line(view: []u8, px: i32, py: i32, dx: i32, dy: i32) void {
    const n: i32 = @intCast(@max(1, @max(@abs(dx), @abs(dy))));
    var i: i32 = 0;
    while (i < LEN) : (i += 1) {
        const x = px - @divTrunc(dx * i, n);
        const y = py - @divTrunc(dy * i, n);
        if (x >= 0 and x < scroll.WIN_W and y >= 0 and y < scroll.VIEW_H) view[@intCast(y * scroll.WIN_W + x)] = if (i < HEAD) ink else tail;
    }
}

/// The palette's two most fiery colours: red + green - 2 blue, ST guns.
fn fiery() void {
    var top: [2]i32 = .{ -99, -99 };
    var idx: [2]u8 = .{ 1, 1 };
    for (1..16) |i| {
        const w = pal.hw[i];
        const f = @as(i32, w >> 8 & 7) + @as(i32, w >> 4 & 7) - 2 * @as(i32, w & 7);
        if (f > top[0]) {
            top[1] = top[0];
            idx[1] = idx[0];
            top[0] = f;
            idx[0] = @intCast(i);
        } else if (f > top[1]) {
            top[1] = f;
            idx[1] = @intCast(i);
        }
    }
    ink = idx[0];
    tail = idx[1];
}
