// --------------------------------------------------------------------------
// The enemies' movement (the model's c_enemy.py, literal): the chase on
// ladders (+$48), the walk / patrol with its gravity, and the turn $3D25A,
// all through the tile collision $3D4C2 (enemy_tiles.zig).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const hit = @import("hit.zig");
const world = @import("world.zig");
const tiles = @import("enemy_tiles.zig").tiles;

const RICK_X: i64 = 0x3A1D4;
const RICK_Y: i64 = 0x3A1D6;

/// Chasing (+$48): line up with Rick in y (2 px, up/down), then in x (2 px).
pub fn climb(a0: i64) void {
    if (m.rb(a0 + 0x4A) != 0) return;
    var d6 = m.rw(a0 + 4);
    const y = m.rw(a0 + 6);
    m.ww(a0 + 8, 0x100);
    m.wb(hit.HIT_MASK, 0x7F);
    const ry = m.rw(RICK_Y);
    if ((y & ~@as(i64, 1)) != (ry & ~@as(i64, 1)) and climbY(a0, d6, y, ry)) return;
    const d7 = m.rw(a0 + 6);
    const rx = m.rw(RICK_X);
    if (d6 == rx) return;
    if (m.s16(d6) >= m.s16(rx)) {
        m.ww(a0 + 2, 0xFF);
        d6 = (d6 - 2) & 0xFFFF;
    } else {
        m.ww(a0 + 2, 0);
        d6 = (d6 + 2) & 0xFFFF;
    }
    if (tiles(d6, d7)) return;
    m.ww(a0 + 4, d6);
    hit.addW(a0 + 0x2A, 1);
    climbEnd(a0);
}

/// 2 px toward Rick's y. False only when the way up is blocked: the x
/// line-up follows then.
fn climbY(a0: i64, d6: i64, d7_: i64, ry: i64) bool {
    if (m.s16(d7_) >= m.s16(ry)) {
        const d7 = (d7_ - 2) & 0xFFFF;
        if (tiles(d6, d7)) return false;
        m.ww(a0 + 8, 0xFE00);
        m.ww(a0 + 6, d7);
        hit.addW(a0 + 0x2A, 1);
        climbEnd(a0);
        return true;
    }
    const d7 = (d7_ + 2) & 0xFFFF;
    if (tiles(d6, d7)) {
        stopClimb(a0);
        return true;
    }
    m.ww(a0 + 6, d7);
    hit.addW(a0 + 0x2A, 1);
    climbEnd(a0);
    return true;
}

/// $3D0B4: still on a ladder (hit_result bit1)? else stop chasing.
fn climbEnd(a0: i64) void {
    if (m.rb(hit.HIT_RESULT) & 2 != 0) return;
    stopClimb(a0);
}

fn stopClimb(a0: i64) void {
    m.wb(a0 + 0x48, 0);
    m.ww(a0 + 0x2A, 2);
    m.ww(a0 + 0xA, 0);
}

/// x snaps to the ladder column (low byte & $F0 | 4).
fn grabLadder(a0: i64, d6: i64) void {
    m.ww(a0 + 4, (d6 & 0xFF00) | (d6 & 0xF0) | 4);
}

/// btst #3,d6 / andi.b #7: an x in the right half of a column must be 8-aligned.
fn ladderOk(d6: i64) bool {
    return !(d6 & 8 != 0 and d6 & 7 != 0);
}

fn chase(a0: i64) void {
    m.ww(a0 + 0xA, 0);
    m.wb(a0 + 0x48, 0xFF);
    m.ww(a0 + 0x2A, 0);
}

/// Not chasing: gravity (y:yfrac += vy, vy += $80 up to $800) until the
/// floor, then walk.
pub fn walk(a0: i64, beh: i64) void {
    const d6 = m.rw(a0 + 4);
    const d1 = (m.rw(a0 + 6) << 16) | m.rw(a0 + 0xA);
    var d7 = ((m.s16(m.rw(a0 + 8)) << 8) + d1) & 0xFFFFFFFF;
    d7 = ((d7 << 16) | (d7 >> 16)) & 0xFFFFFFFF; // swap: low word = new y
    m.wb(hit.HIT_MASK, 0xFF);
    if (!tiles(d6, d7)) {
        m.ww(a0 + 6, d7);
        m.ww(a0 + 0xA, d7 >> 16);
        hit.addW(a0 + 8, 0x80);
        if (m.s16(m.rw(a0 + 8)) > 0x800) m.ww(a0 + 8, 0x800);
        return;
    }
    land(a0, beh, d6, d7);
}

/// On something: a ladder down (behaviour 2), else stand on the floor, a
/// ladder up (behaviour 2), else walk 2 px on.
fn land(a0: i64, beh: i64, d6_: i64, d7_: i64) void {
    var d6 = d6_;
    var d7 = d7_;
    const ry = m.s16(m.rw(RICK_Y));
    if (beh == 2 and m.rb(hit.HIT_RESULT) & 0x80 != 0 and !(m.s16(d7) > ry) and ladderOk(d6)) {
        grabLadder(a0, d6); // a ladder down under the feet
        m.wb(a0 + 7, (m.rb(a0 + 7) & 0xF8) | 5);
        return chase(a0);
    }
    m.wb(a0 + 7, (m.rb(a0 + 7) & 0xF8) | 3); // stand on the floor
    d7 = (d7 & 0xFFFF0000) | m.rw(a0 + 6);
    m.ww(a0 + 0xA, 0);
    m.ww(a0 + 8, 0x100);
    if (beh == 2) {
        _ = tiles(d6, d7);
        if (m.rb(hit.HIT_RESULT) & 2 != 0 and m.s16(d7) > ry and ladderOk(d6)) {
            grabLadder(a0, m.rw(a0 + 4)); // a ladder up
            return chase(a0);
        }
    }
    if (m.rb(a0 + 0x4A) != 0) return;
    d6 = if (m.rw(a0 + 2) != 0) (d6 - 2) & 0xFFFF else (d6 + 2) & 0xFFFF;
    if (tiles(d6, d7)) return turn(a0, true);
    m.ww(a0 + 4, d6);
    m.ww(a0 + 6, d7);
    hit.addW(a0 + 0x2A, 1);
    patrol(a0, beh, d6);
}

/// The walk's end: behaviour 0 counts its patrol down; 1 and 2 decide at anim 8.
fn patrol(a0: i64, beh: i64, d6: i64) void {
    if (beh == 0) {
        hit.addW(a0 + 0x2C, -2);
        if (m.s16(m.rw(a0 + 0x2C)) <= 0) turn(a0, true);
        return;
    }
    if (m.rw(a0 + 0x2A) != 8) return;
    const d = m.rw(a0 + 2);
    if (beh != 1) {
        world.rng();
        if (m.rb(0x39049) & 3 != 0) return;
        return turn(a0, false);
    }
    if (m.s16(d6) > m.s16(m.rw(RICK_X))) {
        if (d != 0) return;
    } else if (d == 0) return;
    turn(a0, false);
}

/// $3D25A: patrol counter = +$30 (on a wall / the counter's end), then
/// $3D260: anim 0, dir toggled.
fn turn(a0: i64, reload: bool) void {
    if (reload) m.ww(a0 + 0x2C, m.rw(a0 + 0x30));
    m.ww(a0 + 0x2A, 0);
    m.ww(a0 + 2, if (m.rw(a0 + 2) != 0) 0 else 0xFF);
}
