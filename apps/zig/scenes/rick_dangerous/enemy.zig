// --------------------------------------------------------------------------
// The enemies, types 4-15 ($3CE1E..$3CF64) -> $3CF76 (the model's
// c_enemy.py, literal): the tile collision $3D4C2, the deadly-object test
// $3D332, the death $3D2FE. d6/d7 are the 68000's registers (d7 kept 32-bit
// where the original keeps its upper word).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const hit = @import("hit.zig");
const snd = @import("sound.zig");
const move = @import("enemy_move.zig");

/// Type -> behaviour (0 wait/patrol, 1 patrol toward Rick, 2 chase via ladders),
/// sprite base, and the alternate base when trigger bit7 (none for behaviour 2).
pub fn handler(a0: i64, ty: i64) void {
    const k = ty - 4;
    const beh = @mod(k, 3);
    const set = @divFloor(k, 3);
    const bases = [4]i64{ 0x0000, 0x0D20, 0x1A40, 0x2760 };
    const alts = [4]i64{ 0x8B20, 0x95A0, 0xA020, 0xAAA0 };
    m.wl(a0 + 0x22, bases[@intCast(set)]);
    if (beh != 2 and m.rb(a0 + 0x46) & 0x80 != 0) m.wl(a0 + 0x22, alts[@intCast(set)]);
    enemy(a0, beh);
}

/// $3D2FE: falling = $FF, yfrac = 0, vy = $FD00, +50, scream, record dead if bit0.
pub fn dies(a0: i64) void {
    m.wb(a0 + 0x49, 0xFF);
    m.ww(a0 + 0xA, 0);
    m.ww(a0 + 8, 0xFD00);
    hit.scoreAdd(0x50);
    snd.play(0x13, 0);
    if (m.rb(a0 + 0x46) & 1 != 0) hit.markUsed(a0);
}

fn overlap(a0: i64, bx: i64, by: i64, bw: i64, bh: i64) bool {
    var d0 = m.s16(m.rw(a0 + 4) + 4 - bw);
    if (d0 >= bx) return false;
    if (m.s16(d0 + bw + 0xF) < bx) return false;
    d0 = m.s16(m.rw(a0 + 6) - bh);
    if (d0 >= by) return false;
    if (m.s16(d0 + bh + 0x14) < by) return false;
    return true;
}

/// $3D332: the enemy overlaps the platform (slot 0, alive) or a deadly object
/// (slots 4-8 with type != 0 and +$3A != 0).
fn deadlyObject(a0: i64) bool {
    if (m.rw(0x3A184) != 0 and overlap(a0, hit.rws(0x3A188), hit.rws(0x3A18A), m.rw(0x3A194), m.rw(0x3A196)))
        return true;
    var a1: i64 = 0x3A2B4;
    while (a1 != 0x3A430) : (a1 += 0x4C) {
        if (m.rw(a1) != 0 and m.rw(a1 + 0x3A) != 0 and
            overlap(a0, hit.rws(a1 + 4), hit.rws(a1 + 6), m.rw(a1 + 0x10), m.rw(a1 + 0x12))) return true;
    }
    return false;
}

/// $3CF76(d0.b = behaviour).
fn enemy(a0: i64, beh: i64) void {
    if (m.rb(a0 + 0x49) != 0) {
        fall(a0);
        return tail(a0);
    }
    if (hit.blastHits(a0)) {
        hit.scoreAdd(0x50);
        dies(a0);
        return anim(a0);
    }
    if (hit.bulletHits(a0)) {
        dies(a0);
        return anim(a0);
    }
    if (m.rb(a0 + 0x4A) != 0) m.wb(a0 + 0x4A, m.rb(a0 + 0x4A) - 1);
    if (hit.pokeHits(a0)) m.wb(a0 + 0x4A, 0x19);
    m.wb(hit.HIT_RESULT, 0);
    if (m.rb(a0 + 0x48) != 0) move.climb(a0) else move.walk(a0, beh);
    tail(a0);
}

/// Dead: x-1 (dir 0) or y+1 (dir != 0), then y += vy (8.8), vy += $C4.
fn fall(a0: i64) void {
    if (m.rw(a0 + 2) == 0) hit.addW(a0 + 4, -1) else hit.addW(a0 + 6, 1);
    const d1 = (m.rw(a0 + 6) << 16) | m.rw(a0 + 0xA);
    const d7 = ((m.s16(m.rw(a0 + 8)) << 8) + d1) & 0xFFFFFFFF;
    m.ww(a0 + 6, d7 >> 16);
    m.ww(a0 + 0xA, d7);
    hit.addW(a0 + 8, 0xC4);
    hit.addW(a0 + 0x2A, 1);
}

/// $3D276: alive: touching Rick kills him; a deadly tile (hit_result bit2)
/// or a deadly object kills the enemy. Then the frame.
fn tail(a0: i64) void {
    if (m.rb(a0 + 0x49) == 0) {
        if (hit.touchesRick(a0)) m.ww(0x3B9B0, 0xFF);
        if (m.rb(hit.HIT_RESULT) & 4 != 0 or deadlyObject(a0)) dies(a0);
    }
    anim(a0);
}

/// $3D29E: frame = anim_i (> 7 wraps to 0) / 2; the sprite offset from
/// $36714 (falling), $36700 (climbing) or $366EC (+$3F0 facing left).
fn anim(a0: i64) void {
    var d1 = m.s16(m.rw(a0 + 0x2A));
    if (d1 > 7) {
        m.ww(a0 + 0x2A, 0);
        d1 = 0;
    } else {
        d1 = ((d1 & ~@as(i64, 1)) * 2) & 0xFFFF;
    }
    var off: i64 = undefined;
    if (m.rb(a0 + 0x49) != 0) {
        off = m.rl(m.idx(0x36714, d1));
    } else if (m.rb(a0 + 0x48) != 0) {
        off = m.rl(m.idx(0x36700, d1));
    } else {
        off = m.rl(m.idx(0x366EC, d1));
        if (m.rw(a0 + 2) != 0) off += 0x3F0;
    }
    m.wl(a0 + 0x22, m.rl(a0 + 0x22) + off);
}
