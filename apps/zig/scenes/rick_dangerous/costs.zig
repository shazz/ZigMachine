// --------------------------------------------------------------------------
// What the borrowed work costs the long calls' clock (the model's a_clock.py):
// the erase $3A70E and the draw $3AB14 from their 68000 cycle structure, and
// each handler type by its median over the dumps. These are the model's
// estimates (FINAL.md 7.1): the VBL count they give is right on every dump.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");

const ERASE_BASE: i64 = 2144;
const HANDLER_ENEMY: i64 = 3888;
const HANDLER_TRAP: i64 = 428;

/// $3A70E's cost over the slots (a_clock.erase_cost).
pub fn eraseCost() i64 {
    var n = ERASE_BASE;
    var a = F.ENT;
    const rect_off: i64 = if (m.rl(F.SCREEN_PTR) & 0x8000 != 0) 0x16 else 0x1C;
    while (m.rw(a) != 0xFFFF) : (a += F.ENT_SZ) {
        const r = a + rect_off;
        const fl = m.rb(r);
        const alive = m.rw(a) != 0;
        if (!alive and fl & 4 == 0) continue;
        n += if (alive) 12 else 48;
        if (fl & 1 == 0) continue;
        if (m.rb(F.SCROLL_ON) != 0) {
            n += 20;
        } else {
            const k = @min(m.rw(r + 2), 0x14);
            n += if (fl & 2 != 0) eraseWide(k) else eraseNarrow(k);
        }
    }
    return n;
}

fn eraseNarrow(k: i64) i64 {
    return if (k == 0x14) 2136 else 248 + 108 * k;
}
fn eraseWide(k: i64) i64 {
    return if (k == 0x14) 2976 else 276 + 148 * k;
}

/// A handler's cost: the median of its type over the dumps.
pub fn handlerCost(ty: i64) i64 {
    return switch (ty) {
        1 => 3196,
        2 => 520,
        3 => 504,
        10 => 4100,
        12 => 4800,
        13 => 4124,
        14 => 3080,
        15 => 2896,
        18 => 480,
        19, 20, 21 => 444,
        22, 23 => 268,
        24 => 716,
        26 => 448,
        42 => 848,
        57, 63 => 736,
        66 => 884,
        4...9, 11 => HANDLER_ENEMY,
        else => HANDLER_TRAP,
    };
}

/// The bounds check + blit of $3AB14, from its cycle structure.
pub fn drawCost(slot: i64) i64 {
    const a = F.ENT + F.ENT_SZ * slot;
    const x = m.sw(a + 4);
    const y = m.sw(a + 6);
    if (x < -8 or x > 0xF0 or y < 0 or y > 0x142) return 250;
    var h = m.rw(a + 0x14);
    if (h == 0) h = 0x15;
    if (m.rl(a + 0x22) == 0 or x < 0 or x > 0xE8) return 300;
    var extra: i64 = 0;
    if (y < 0x40) {
        if (y <= 0x40 - h) return 330;
        h -= 0x40 - y;
        extra = 64;
    } else if (y > 0xFF - h) {
        if (y >= 0xFF) return 404;
        h = 0x100 - y;
        extra = 32;
    }
    const s = x & 15;
    if (s == 0) return 528 + extra + 344 * h;
    const r = (8 + 2 * s + 3) & ~@as(i64, 3);
    return 560 + extra + (612 + 10 * r) * h;
}
