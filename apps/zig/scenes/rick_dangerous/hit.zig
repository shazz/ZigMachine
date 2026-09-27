// --------------------------------------------------------------------------
// The actors' helpers (the model's c_hit.py, literal): kill a slot $3A6C0,
// the score add $3AE66, mark a spawn record dead $3D4B2, and the hit tests
// $3C6CE / $3C672 / $3C692 / $3C714 / $3D408 / $3D42C, the bullet against
// the walls $3C77E. `a0` is the slot's ABSOLUTE address; carry-returning
// routines return a bool (true = carry set).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const core = @import("core.zig");
const draw = @import("draw.zig");

pub const BULLET: i64 = 0x3A21C; // slot 2
pub const DYNAMITE: i64 = 0x3A268; // slot 3
pub const RICK: i64 = 0x3A1D0; // slot 1
pub const PLATFORM: i64 = 0x3A184; // slot 0
pub const HIT_MASK: i64 = 0x3D6AA;
pub const HIT_RESULT: i64 = 0x3D6AB;

/// add.w / addi.w / subi.w on the word at a (wraps).
pub fn addW(a: i64, d: i64) void {
    m.ww(a, m.rw(a) + d);
}

/// The signed word at a.
pub fn rws(a: i64) i64 {
    return m.sw(a & 0xFFFFFF);
}

/// $3A6C0 (draw.zig owns the one transcription).
pub const killSlot = draw.killSlot;

/// $3AE66(d0 = BCD long): into score_bcd $3ADA8..$3ADAA (abcd, X cleared),
/// the 6 digits to $3ADB2.., dirty_score = $FF.
pub fn scoreAdd(d0: i64) void {
    m.wl(0x3AFA0, d0);
    var x: i64 = 0;
    var k: i64 = 2;
    while (k >= 0) : (k -= 1) {
        const r = core.bcdAdd(m.rb(0x3ADA8 + k), m.rb(0x3AFA1 + k), x);
        m.wb(0x3ADA8 + k, r.r);
        x = r.c;
    }
    k = 2;
    while (k >= 0) : (k -= 1) {
        const b = m.rb(0x3ADA8 + k);
        m.wb(0x3ADB3 + 2 * k, b & 15);
        m.wb(0x3ADB2 + 2 * k, b >> 4);
    }
    m.wb(0x3ADD2, 0xFF);
}

/// $3D4B2: bset #7,2(spawn_rec): the record stays dead until the next game.
pub fn markUsed(a0: i64) void {
    const a = (m.rl(a0 + 0x26) + 2) & 0xFFFFFF;
    m.wb(a, m.rb(a) | 0x80);
}

/// $3C6CE: d0.w = 0 -> no; else is (d1, d2) inside the slot's box?
pub fn pointInBox(a0: i64, d0: i64, d1_: i64, d2_: i64) bool {
    if (d0 & 0xFFFF == 0) return false;
    const d1 = m.s16(d1_);
    const d2 = m.s16(d2_);
    const x = rws(a0 + 4);
    if (x > d1 or m.s16(x - 1 + m.rw(a0 + 0x10)) < d1) return false;
    const y = rws(a0 + 6);
    if (y > d2 or m.s16(y - 1 + m.rw(a0 + 0x12)) < d2) return false;
    return true;
}

/// $3C672: the poke hot spot in the slot's box.
pub fn pokeHits(a0: i64) bool {
    return pointInBox(a0, m.rw(0x3B9A0), m.rw(0x3B9A2), m.rw(0x3B9A4));
}

/// $3C692: the bullet in the slot's box: the bullet dies.
pub fn bulletHits(a0: i64) bool {
    if (!pointInBox(a0, m.rw(BULLET), m.rw(0x3B9A6), m.rw(0x3B9A8))) return false;
    m.ww(BULLET, 0);
    m.wb(0x3A232, m.rb(0x3A232) | 4);
    m.wb(0x3A238, m.rb(0x3A238) | 4);
    return true;
}

/// $3C714: blast_on and the blast box overlaps the slot.
pub fn blastHits(a0: i64) bool {
    if (m.rw(0x3B9AA) == 0) return false;
    const w = m.rw(a0 + 0x10);
    const h = m.rw(a0 + 0x12);
    const x = rws(a0 + 4);
    const y = rws(a0 + 6);
    const d0 = m.s16(m.rw(0x3B9AC) - 0x10 - w);
    if (d0 >= x) return false;
    if (m.s16(d0 + 0x1F + w) < x) return false;
    const d1 = m.s16(m.rw(0x3B9AE) - 0xE - h);
    if (d1 >= y) return false;
    if (m.s16(d1 + 0x1C + h) < y) return false;
    return true;
}

/// $3D408: zone_x <= d0 <= zone_w(x1) and zone_y <= d1 <= zone_h(y1), signed.
pub fn inZone(a0: i64, d0_: i64, d1_: i64) bool {
    const d0 = m.s16(d0_);
    const d1 = m.s16(d1_);
    if (d0 < rws(a0 + 0x3C) or d1 < rws(a0 + 0x3E)) return false;
    if (d0 > rws(a0 + 0x40) or d1 > rws(a0 + 0x42)) return false;
    return true;
}

/// $3D42C: not while Rick dies; Rick's body against the slot's w/h.
pub fn touchesRick(a0: i64) bool {
    if (m.rb(0x3B99A) != 0) return false;
    const w = m.rw(a0 + 0x10);
    const h = m.rw(a0 + 0x12);
    const x = rws(a0 + 4);
    const y = rws(a0 + 6);
    var d0 = m.s16(m.rw(0x3A1D4) + 5 - w);
    if (d0 >= x) return false;
    if (m.s16(d0 + w + 0xD) < x) return false;
    const ladder = m.rb(0x3B996) != 0;
    const lift: i64 = if (ladder) 8 else 0;
    d0 = m.s16(m.rw(0x3A1D6) + lift - h);
    if (d0 >= y) return false;
    if (m.s16(d0 + h + 0x14 - lift) < y) return false;
    return true;
}

/// (Rick x + $B, Rick y + $A), the point the trigger zones test.
pub fn hotX() i64 {
    return (m.rw(0x3A1D4) + 0xB) & 0xFFFF;
}
pub fn hotY() i64 {
    return (m.rw(0x3A1D6) + 0xA) & 0xFFFF;
}

/// $3C77E(d6 x, d7 y): a wall tile (attr bit6) under the point, or the platform.
pub fn bulletWall(d6: i64, d7: i64) bool {
    const d4 = m.s16(d6);
    const d5 = m.s16(d7);
    const col = (d6 & 0xFFFF) >> 3;
    const row = (((d7 & 0xFF00) | (d7 & 0xF8)) * 4) & 0xFFFF;
    const tile = m.rb(m.idx(m.idx(0x39C00, col), row));
    if (m.rb((m.rl(0x39056) + tile) & 0xFFFFFF) & 0x40 != 0) return true;
    if (m.rw(PLATFORM) == 0) return false;
    const px = rws(0x3A188);
    if (d4 < px or d4 >= m.s16(px + m.rw(0x3A194))) return false;
    const py = rws(0x3A18A);
    if (d5 < py or d5 >= m.s16(py + m.rw(0x3A196))) return false;
    return true;
}
