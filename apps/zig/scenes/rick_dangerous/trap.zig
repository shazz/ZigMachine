// --------------------------------------------------------------------------
// The trap interpreter $3CBDE (types 24-73) and the intro picture $3B2D8
// (type 74): the model's c_trap.py, literal. Nothing is per-trap: the spawn
// filled the slot from the type descriptor $377B6, and the loop walks
//   the anim list   longs (sprite pointers), -1 = loop to the first (and,
//                   when the sound has bit7, the sound again)
//   the path        6-byte records (count.w, dx.w, dy.w), $FFFF = the end
//   the flags +$46  bit7 Rick's hot spot in the zone, bit6 poked, bit5 shot
//                   (bit1: absorbs the bullet), bit4 blast, bit3 deadly
//                   while moving, bit2 deadly while idle, bit0 removed at the end
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const hit = @import("hit.zig");
const snd = @import("sound.zig");

/// $3CBDE.
pub fn trap(a0: i64) void {
    if (m.rb(a0 + 0x47) != 0) return run(a0);
    m.ww(a0 + 0x3A, 0);
    const fl = m.rb(a0 + 0x46);
    if (fl & 4 != 0) { // deadly while idle
        m.wb(a0 + 0x3A, 0xFF);
        if (hit.touchesRick(a0)) m.ww(0x3B9B0, 0xFF);
    }
    if (m.rb(0x3B99A) != 0) return;
    if (!triggered(a0, fl)) return;
    m.wb(a0 + 0x47, 0xFF);
    const d0 = m.rw(a0 + 0x44);
    if (d0 != 0) snd.play(d0 & ~@as(i64, 0x80), 0);
}

fn triggered(a0: i64, fl: i64) bool {
    if (fl & 0x80 != 0 and hit.inZone(a0, hit.hotX(), hit.hotY())) return true;
    if (fl & 0x40 != 0 and m.rw(0x3B9A0) != 0 and hit.inZone(a0, m.rw(0x3B9A2), m.rw(0x3B9A4))) return true;
    if (fl & 0x20 != 0 and m.rw(hit.BULLET) != 0 and hit.inZone(a0, m.rw(0x3B9A6), m.rw(0x3B9A8))) {
        m.ww(hit.BULLET, 0);
        if (fl & 2 != 0) {
            hit.killSlot(hit.BULLET);
        } else {
            m.wb(0x3A232, m.rb(0x3A232) | 4);
            m.wb(0x3A238, m.rb(0x3A238) | 4);
        }
        return true;
    }
    if (fl & 0x10 != 0 and m.rw(0x3B9AA) != 0 and hit.inZone(a0, m.rw(0x3B9AC), m.rw(0x3B9AE))) return true;
    return false;
}

/// $3CCFA: triggered: deadly (bit3), the next anim frame, the next path
/// step, the end of the path.
fn run(a0: i64) void {
    m.ww(a0 + 0x3A, 0);
    if (m.rb(a0 + 0x46) & 8 != 0) {
        m.wb(a0 + 0x3A, 0xFF);
        if (hit.touchesRick(a0)) m.ww(0x3B9B0, 0xFF);
    }
    nextFrame(a0);
    const a1 = m.rl(a0 + 0x36) & 0xFFFFFF;
    const rec = m.idx(a1, m.rw(a0 + 0x2C) * 6);
    if (m.rw(rec) != 0xFFFF) {
        hit.addW(a0 + 4, m.rw(rec + 2));
        hit.addW(a0 + 6, m.rw(rec + 4));
        hit.addW(a0 + 0x2E, 1);
        if (!(hit.rws(a0 + 0x2E) < hit.rws(rec))) {
            m.ww(a0 + 0x2E, 0);
            hit.addW(a0 + 0x2C, 1);
        }
        const x = hit.rws(a0 + 4);
        const y = hit.rws(a0 + 6);
        if (-8 <= x and x <= 0xF0 and 0 <= y and y <= 0x142) return;
    }
    if (m.rb(a0 + 0x46) & 1 != 0) return hit.killSlot(a0);
    m.wb(a0 + 0x47, 0); // back home, dormant again
    m.ww(a0 + 0x2A, 0);
    m.ww(a0 + 0x2E, 0);
    m.ww(a0 + 0x2C, 0);
    m.ww(a0 + 4, m.rw(a0 + 0xC));
    m.ww(a0 + 6, m.rw(a0 + 0xE));
    m.wl(a0 + 0x22, m.rl(m.rl(a0 + 0x32) & 0xFFFFFF));
}

fn nextFrame(a0: i64) void {
    const a1 = m.rl(a0 + 0x32) & 0xFFFFFF;
    var d0 = (m.rw(a0 + 0x2A) + 1) & 0xFFFF;
    var d1 = m.rl(m.idx(a1, d0 << 2));
    if (d1 == 0xFFFFFFFF) {
        const s = m.rw(a0 + 0x44);
        if (s & 0x80 != 0 and s & ~@as(i64, 0x80) != 0) snd.play(s & ~@as(i64, 0x80), 0);
        d0 = 1;
        d1 = m.rl(a1 + 4);
        if (d1 == 0xFFFFFFFF) {
            d1 = m.rl(a1);
            d0 = 0;
        }
    }
    m.ww(a0 + 0x2A, d0);
    m.wl(a0 + 0x22, d1);
}

/// Type 74, $3B2D8 (slot 12 on the level intro screen): the same scheme with
/// absolute addresses: anim list $3A546 (byte offset $3A53E, loops on -1),
/// path $3A54A of 10-byte records (count.w, dx.w, dy.w, next anim list.l;
/// count 0 = the end), step $3A540, counter $3A542.
pub fn introPicture(a0: i64) void {
    const a1 = m.rl(0x3A54A) & 0xFFFFFF;
    const d0 = (m.rw(0x3A540) * 10) & 0xFFFF;
    if (m.rl(0x3A546) == 0) return;
    const a2 = m.rl(0x3A546) & 0xFFFFFF;
    var d1 = m.rw(0x3A53E);
    var d2 = m.rl(m.idx(a2, d1));
    if (d2 == 0xFFFFFFFF) {
        d1 = 0;
        d2 = m.rl(a2);
    }
    m.ww(0x3A53E, d1);
    m.wl(a0 + 0x22, d2);
    hit.addW(0x3A53E, 4);
    var rec = m.idx(a1, d0);
    if (m.rw(rec) == 0) return;
    hit.addW(0x3A518, m.rw(rec + 2));
    hit.addW(0x3A51A, m.rw(rec + 4));
    hit.addW(0x3A542, 1);
    if (hit.rws(0x3A542) <= hit.rws(rec)) return;
    m.ww(0x3A542, 0);
    hit.addW(0x3A540, 1);
    m.ww(0x3A53E, 0);
    rec = m.idx(a1, d0 + 10);
    if (m.rw(rec) == 0) return;
    m.wl(0x3A546, m.rl(rec + 6));
}
