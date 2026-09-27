// --------------------------------------------------------------------------
// $391C4: a slot filled from its spawn record and its type descriptor $377B6
// (the model's a_spawn.py, literal; the record's layout is in spawn.zig).
// Returns the ORIGINAL's cycles, as the rest of spawn.zig does.
// --------------------------------------------------------------------------
const m = @import("ram.zig");

const TYPES: i64 = 0x377B6;
const FILL: i64 = 1012;

/// $391C4(a0 = record, a1 = slot, d0 = row offset).
pub fn fill(a0: i64, a1: i64, d0: i64) i64 {
    m.wl(a1 + 0x26, a0);
    const t = m.rb(a0 + 2);
    m.ww(a1, t);
    const a2 = TYPES + ((t << 4) & 0xFFFF);
    m.ww(a1 + 0x10, m.rw(a2 + 2));
    m.ww(a1 + 0x12, m.rw(a2 + 4));
    m.ww(a1 + 0x44, m.rw(a2));
    m.wl(a1 + 0x36, m.rl(a2 + 0xA));
    m.ww(a1 + 0x40, m.rb(a2 + 0xE) << 3);
    m.ww(a1 + 0x42, m.rb(a2 + 0xF) << 3);
    m.wl(a1 + 0x22, 0);
    const anim = m.rl(a2 + 6);
    m.wl(a1 + 0x32, anim);
    if (anim != 0) m.wl(a1 + 0x22, m.rl(anim & 0xFFFFFF));
    place(a0, a1, d0);
    zone(a0, a1, d0);
    defaults(a0, a1);
    return FILL + @as(i64, if (anim != 0) 20 else 0);
}

fn place(a0: i64, a1: i64, d0: i64) void {
    var d2 = m.rb(a0 + 4);
    const d1 = d2 & 0xF8;
    d2 = ((((d2 & 7) + d0) & 0xFFFF) << 3) & 0xFFFF;
    if (m.rb(a0 + 3) & 4 == 0) d2 = (d2 & 0xFF00) | (d2 & 0xF8) | 3;
    m.ww(a1 + 6, d2);
    m.ww(a1 + 4, d1);
    m.ww(a1 + 0xC, d1);
    m.ww(a1 + 0xE, d2);
}

fn zone(a0: i64, a1: i64, d0: i64) void {
    var d2 = m.rb(a0 + 5);
    const d1 = d2 & 0xF8;
    d2 &= 7;
    m.wb(a1 + 0x4A, d2);
    d2 = (((d2 + d0) & 0xFFFF) << 3) & 0xFFFF;
    m.ww(a1 + 0x3E, d2);
    m.ww(a1 + 0x42, m.rw(a1 + 0x42) + d2);
    m.wb(a1 + 0x4A, m.rb(a1 + 0x4A) * 0x19);
    m.ww(a1 + 0x3C, d1);
    m.ww(a1 + 0x30, d1);
    m.ww(a1 + 0x40, m.rw(a1 + 0x40) + d1);
}

fn defaults(a0: i64, a1: i64) void {
    m.ww(a1 + 0x3A, if (m.rb(a0 + 3) & 4 != 0) 0xFF else 0);
    m.wb(a1 + 0x46, m.rb(a0 + 3));
    m.ww(a1 + 0x2A, 0);
    m.ww(a1 + 0x2C, 0);
    m.ww(a1 + 0x2E, 0);
    m.wb(a1 + 0x47, 0);
    m.ww(a1 + 2, 0xFF);
    m.wb(a1 + 0x48, 0);
    m.wb(a1 + 0xA, 0);
    m.ww(a1 + 8, 0x100);
    m.wb(a1 + 0x49, 0);
}
