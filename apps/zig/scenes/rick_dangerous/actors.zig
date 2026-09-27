// --------------------------------------------------------------------------
// The actors that are not enemies or traps (the model's pkg_c.py, literal):
// the bullet (type 2), the dynamite and its blast (3), the dynamite / bullet
// boxes (16 / 17), the treasures (18-21), the timed-bonus zones (22 / 23),
// and the timed-bonus countdown (call 11).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const core = @import("core.zig");
const hit = @import("hit.zig");
const snd = @import("sound.zig");

/// Call 11, $3B8AA: while a timed bonus runs, every 25 frames the value
/// -= $0010 (BCD, the word at $3B8A0); it stops at 0.
pub fn bonusTimer() void {
    if (m.rw(0x3B89A) == 0) return;
    m.ww(0x3B89C, m.rw(0x3B89C) - 1);
    if (m.rw(0x3B89C) != 0) return;
    m.ww(0x3B89C, 0x19);
    var x: i64 = 0; // andi.b #$ee,ccr clears X
    for ([2]i64{ 1, 0 }) |k| { // sbcd -(a1),-(a0) twice: low byte first
        const r = core.bcdSub(m.rb(0x3B89E + k), m.rb(0x3B8A0 + k), x);
        m.wb(0x3B89E + k, r.r);
        x = r.c;
    }
    if (m.rw(0x3B89E) == 0) m.ww(0x3B89A, 0);
}

/// Type 2, $3C4DC: 8 px a frame; a wall at the NEW bullet_x kills it.
pub fn bullet(a0: i64) void {
    var d6 = m.rw(0x3B9A6);
    const d7 = m.rw(0x3B9A8);
    if (m.rw(0x3A21E) == 0) {
        m.ww(0x3A220, m.rw(0x3A220) + 8);
        d6 = (d6 + 8) & 0xFFFF;
    } else {
        m.ww(0x3A220, m.rw(0x3A220) - 8);
        d6 = (d6 - 8) & 0xFFFF;
    }
    if (hit.bulletWall(d6, d7)) return hit.killSlot(a0);
    m.ww(0x3B9A6, d6);
}

/// Type 3, $3C52A: the fuse (anim $36674, sfx 9 every 4th frame), then the
/// blast: the slot moves -4/-5, digi 10 twice, the blast box live for anim
/// frames 0-6 ($366C0); Rick inside it is killed; at the anim's end, all clear.
pub fn dynamite(a0: i64) void {
    if (m.rw(0x3B99C) == 0) {
        m.ww(0x3B9AA, 0);
        const d1 = m.rl(m.idx(0x36674, (m.rw(0x3A292) & ~@as(i64, 1)) * 2));
        if (d1 != 0xFFFFFFFF) {
            m.ww(0x3A292, m.rw(0x3A292) + 1);
            m.wl(0x3A28A, d1);
            if (m.rw(0x3A292) & 3 == 0) snd.play(9, 1);
            return;
        }
        m.ww(0x3B99C, 0xFF);
        m.ww(0x3A26C, m.rw(0x3A26C) - 4);
        m.ww(0x3A26E, m.rw(0x3A26E) - 5);
        m.ww(0x3A27C, 0);
        m.ww(0x3A292, 0);
        snd.play(0xA, 1);
        snd.play(0xA, 0);
    }
    m.ww(0x3B9AC, m.rw(0x3A26C) + 0xC);
    m.ww(0x3B9AE, m.rw(0x3A26E) + 0xA);
    m.ww(0x3B9AA, 0xFF);
    const d0 = m.rw(0x3A292);
    if (!(m.s16(d0) < 7)) m.ww(0x3B9AA, 0);
    const d1 = m.rl(m.idx(0x366C0, (d0 & ~@as(i64, 1)) * 2));
    if (d1 != 0xFFFFFFFF) {
        m.ww(0x3A292, d0 + 1);
        m.wl(0x3A28A, d1);
        if (hit.blastHits(hit.RICK)) m.ww(0x3B9B0, 0xFF);
        return;
    }
    m.ww(hit.DYNAMITE, 0);
    m.ww(0x3B99C, 0);
    m.ww(0x3B9AA, 0);
    hit.killSlot(a0);
}

/// Types 16 / 17, $3CA8E / $3CAA2 -> $3CADA. Poked, shot or blasted: it
/// explodes (digi 10, deadly). Touched: the refill (16 the DYNAMITE, 17 the
/// BULLETS), sfx 16, gone for the game.
pub fn box(a0: i64, ty: i64) void {
    m.wl(a0 + 0x22, if (ty == 16) @as(i64, 0x1EEF0) else 0x1F040);
    if (m.rw(a0 + 0x3A) == 0) {
        if (hit.pokeHits(a0) or hit.bulletHits(a0) or hit.blastHits(a0)) {
            hit.markUsed(a0);
            snd.play(0xA, 0);
            m.ww(a0 + 0x3A, 0xFF);
        } else {
            if (hit.touchesRick(a0)) {
                refill(ty);
                hit.markUsed(a0);
                hit.killSlot(a0);
                snd.play(0x10, 0);
            }
            return;
        }
    }
    const d1 = m.rl(m.idx(0x366C0, (m.rw(a0 + 0x2A) & ~@as(i64, 1)) * 2));
    if (d1 == 0xFFFFFFFF) return hit.killSlot(a0);
    m.ww(a0 + 0x2A, m.rw(a0 + 0x2A) + 1);
    m.wl(a0 + 0x22, d1);
    if (hit.touchesRick(a0)) m.ww(0x3B9B0, 0xFF);
}

fn refill(ty: i64) void {
    if (ty == 16) {
        m.wb(0x3ADAE, 6);
        m.wb(0x3ADD6, 0xFF);
    } else {
        m.wb(0x3ADAC, 6);
        m.wb(0x3ADD4, 0xFF);
    }
}

/// Types 18-21, $3CB84: touched: +500, record dead, sfx 17, then the '500'
/// sprite floats up 2 px a frame for 12 frames and the slot dies.
pub fn treasure(a0: i64, ty: i64) void {
    const d0: i64 = switch (ty) {
        18 => 0,
        19 => 1,
        20 => 3,
        else => 2,
    };
    if (m.rw(a0 + 0x2C) != 0) {
        m.ww(a0 + 0x2C, m.rw(a0 + 0x2C) - 1);
        if (m.rw(a0 + 0x2C) == 0) return hit.killSlot(a0);
        m.wl(a0 + 0x22, 0x27CB0);
        m.ww(a0 + 6, m.rw(a0 + 6) - 2);
        return;
    }
    m.wl(a0 + 0x22, d0 * 0x150 + 0x1F190);
    if (!hit.touchesRick(a0)) return;
    hit.scoreAdd(0x500);
    hit.markUsed(a0);
    m.ww(a0 + 0x2C, 0xC);
    snd.play(0x11, 0);
}

/// Types 22 / 23, $3B8EA / $3B924 -> $3B95E: Rick (not dying, a WORD test of
/// $3B99A) with his hot spot in the zone: the slot dies, the action runs,
/// the record is marked dead if flag bit0.
pub fn bonusZone(a0: i64, ty: i64) void {
    m.wl(a0 + 0x22, 0);
    if (m.rw(0x3B99A) != 0) return;
    if (!hit.inZone(a0, hit.hotX(), hit.hotY())) return;
    hit.killSlot(a0);
    if (ty == 22) bonusStart() else bonusCollect();
    if (m.rb(a0 + 0x46) & 1 != 0) hit.markUsed(a0);
}

/// $3B8FE: bonus on, tick 25, value $2000, sfx 18.
fn bonusStart() void {
    m.ww(0x3B89A, 0xFF);
    m.ww(0x3B89C, 0x19);
    m.ww(0x3B89E, 0x2000);
    snd.play(0x12, 0);
}

/// $3B938: if a bonus runs: tune 7 (sound id 7), stop it, score += what is left.
fn bonusCollect() void {
    if (m.rw(0x3B89A) == 0) return;
    snd.play(7, 0);
    m.ww(0x3B89A, 0);
    hit.scoreAdd(m.rw(0x3B89E));
}
