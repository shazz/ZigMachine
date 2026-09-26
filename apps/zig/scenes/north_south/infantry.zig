// --------------------------------------------------------------------------
// Infantry ($C5B8; soldiers 6-11 of each side) with its helpers $BF54 $BFD8
// $C0E2 $C170, the volley $C2FC and the re-form $C534, from ns.app.
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const u = @import("units.zig");
const Game = @import("game.zig").Game;

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

/// The command for this unit type: the stick when it is selected, or the CPU's.
pub fn cmdFor(g: *Game, s: u32, sel: i32) i32 {
    if (g.m.w(s + ad.S_SEL) == sel or g.m.w(s + ad.S_CPU) == 1) return g.m.w(ad.CMD);
    return 0;
}

/// A row of soldiers in the way of a move: dd drops to 0.
fn blocked(g: *Game, base: u32, n: u32, comptime what: enum { x_hi, x_lo, y_hi, y_lo }, lim: i32, free: bool) bool {
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        const o = base + 12 * k;
        if (g.m.w(o + 6) == 0) continue;
        const hit = switch (what) {
            .x_hi => g.m.w(o) > lim,
            .x_lo => g.m.w(o) < lim,
            .y_hi => g.m.w(o + 2) > lim,
            .y_lo => g.m.w(o + 2) < lim,
        };
        if (hit and free) return true;
    }
    return false;
}

pub fn infantry(g: *Game, s: u32) void { // $C5B8
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    m.setw(ad.ANIM_CHANGE, 0);
    var act = cmdFor(g, s, 1) & 0x7F;
    if (m.w(s + ad.S_ENTER) & 1 != 0) act = if (b != 0) 7 else 3;
    if (m.w(s + ad.S_RETREAT) & 1 != 0) act = if (b != 0) 3 else 7;
    const base = obj(b + 6);
    const free = m.w(s + ad.S_ENTER) & 1 == 0 and m.w(s + ad.S_RETREAT) & 1 == 0;
    var dd: i32 = 0;
    var horiz: i32 = 1;
    switch (act) {
        3 => {
            dd = if (blocked(g, base, 6, .x_hi, 0x134, free)) 0 else 1;
            // column formation when marching BACKWARDS
            if (m.l(s + ad.S_INFFORM) != ad.T_COLUMN + B and b != 0) {
                m.setw(s + ad.S_INFREF, 1);
                m.setl(s + ad.S_INFFORM, ad.T_COLUMN + B);
            }
        },
        5 => {
            horiz = 0;
            dd = if (blocked(g, base, 6, .y_hi, 0xC6, true)) 0 else 1;
        },
        7 => {
            dd = if (blocked(g, base, 6, .x_lo, 2, free)) 0 else -1;
            if (m.l(s + ad.S_INFFORM) != ad.T_COLUMN + B and b == 0) {
                m.setw(s + ad.S_INFREF, 1);
                m.setl(s + ad.S_INFFORM, ad.T_COLUMN + B);
            }
        },
        1 => {
            horiz = 0;
            dd = if (blocked(g, base, 6, .y_lo, 0x0A, true)) 0 else -1;
        },
        else => {
            act = if (m.w(s + ad.S_INFREF) != 0) 1 else 8;
            if (m.w(s + ad.S_VOLLEY) != 0) act = 0x0A;
        },
    }
    act = s16(act) >> 1; // asr.w at $C846
    checkAlive(g, s);
    if (m.w(s + ad.S_INFACT) != act) {
        m.setl(ad.ANIM_NEW, @intCast(@as(i32, ad.A_INF) + act * 10 + @as(i32, B)));
        m.setw(s + ad.S_INFACT, act);
        m.setw(ad.ANIM_CHANGE, 1);
    }
    var k = b + 6;
    while (k < b + 12) : (k += 1) {
        const o = obj(k);
        step(g, o, s, horiz, dd, k);
        bump(g, o, s, horiz, dd, k);
        die(g, o, s);
        if (m.w(o + 6) != 0) u.animStep(g, o);
    }
    volley(g, s);
    reformInf(g, s);
}

fn checkAlive(g: *Game, s: u32) void { // $BF54
    const b = g.m.w(ad.SIDE_BASE);
    var k = b + 6;
    while (k < b + 12) : (k += 1) if (g.m.w(obj(k) + 6) != 0) return;
    if (!u.reinforce(g, 6)) g.m.setw(s + ad.S_ALIVE, g.m.w(s + ad.S_ALIVE) & 0xFFFE);
}

fn step(g: *Game, o: u32, s: u32, horiz: i32, dd: i32, k: i32) void { // $BFD8
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    if (m.w(o + 6) != 3) return;
    if (horiz == 1) {
        m.addw(o, dd);
    } else {
        const v = s16(m.w(o + 2) + dd);
        u.drawMove(g, v, k);
        m.setw(o + 2, v);
    }
    const cell = u.gridAt(g, s16(m.w(o) - @divTrunc(b, 3)), m.w(o + 2));
    if (m.w(s + ad.S_ENTER) & 1 == 0) {
        if (cell != 0) {
            if (cell < 0x64 and m.w(s + ad.S_RETREAT) & 1 == 0 and m.w(s + ad.S_CPU) == 0) m.setw(o + 6, 0x64);
            if (cell == 0x64) m.setw(o + 6, 0x65);
        }
    } else if ((b == 0 and m.w(o) == 0x36) or (b != 0 and m.w(o) == 0xFA)) {
        m.setw(s + ad.S_ENTER, m.w(s + ad.S_ENTER) & 0xFFFE);
    }
    if (m.w(s + ad.S_RETREAT) & 1 != 0) {
        if ((b == 0 and m.w(o) == -45) or (b != 0 and m.w(o) == 0x159))
            m.setw(s + ad.S_ALIVE, m.w(s + ad.S_ALIVE) & 0xFFFE);
    }
}

fn bump(g: *Game, o: u32, s: u32, horiz: i32, dd: i32, k: i32) void { // $C0E2
    const m = &g.m;
    const st = m.w(o + 6);
    if (st != 4 and st != 0x64) return;
    if (st == 0x64) {
        m.setw(o + 6, 4);
        m.setl(o + 8, ad.A_BUMP_INF + B);
        if (horiz == 1) {
            m.setw(o, m.w(o) - s16(dd + m.w(ad.DIR)));
        } else {
            const v = s16(m.w(o + 2) - dd);
            u.drawMove(g, v, k);
            m.setw(o + 2, v);
        }
    }
    if (m.derefW(m.l(o + 8)) == -1) {
        m.setw(o + 6, 3);
        m.setw(s + ad.S_INFACT, 0x14);
    }
}

fn die(g: *Game, o: u32, s: u32) void { // $C170
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    const st = m.w(o + 6);
    if (st != 5 and st != 0x65) return;
    if (st == 0x65) {
        m.setw(o + 6, 5);
        m.setl(o + 8, ad.A_DIE_INF + B);
    }
    if (m.derefW(m.l(o + 8)) != -1) return;
    const cell = u.gridAt(g, s16(m.w(o) - @divTrunc(b, 3)), m.w(o + 2));
    if (cell == 0x64) {
        if (m.w(ad.FIELD) == 0) {
            g.blit(.log, .fx_b, 5, m.w(o), m.w(o + 2));
            g.play(0x11, 0x81);
        } else {
            g.play(0x2E, 0x82);
        }
    } else {
        g.blit(.bg, .cur, 5, m.w(o), m.w(o + 2));
        g.blit(.log, .cur, 5, m.w(o), m.w(o + 2));
        if (g.rnd(2) != 0) g.play(0x1C, 0x81) else g.play(0x2E, 0x82);
    }
    m.setw(o + 6, 0);
    m.setw(s + ad.S_INFACT, 0x14);
    var r: u32 = undefined;
    if (b != 0) {
        m.setw(ad.SIDE_B + ad.S_INFLEAD, u.firstAlive(g, 0x12, 0x18));
        r = m.l(ad.REC_B) -% B;
    } else {
        m.setw(ad.SIDE_A + ad.S_INFLEAD, u.firstAlive(g, 6, 0x0C));
        r = m.l(ad.REC_A) -% B;
    }
    m.setb(r + 1, m.b(r + 1) - 1);
}

fn volley(g: *Game, s: u32) void { // $C2FC
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    var shooters: u16 = 0;
    const v = cmdFor(g, s, 1);
    if (!((v & 0x80 != 0 and m.w(s + ad.S_INFREF) == 0) or m.w(s + ad.S_VOLLEY) != 0)) return;
    if (v & 0x80 != 0 and m.l(s + ad.S_INFFORM) != ad.T_LINE_A + B) {
        m.setw(s + ad.S_INFREF, 1);
        m.setl(s + ad.S_INFFORM, ad.T_LINE_A + B);
        return;
    }
    m.setl(ad.ROW_PTR, s + ad.S_BULLETS + B);
    m.setw(ad.MUZZLE, if (b != 0) 6 else 0x0D);
    var k = b + 6;
    while (k < b + 12) : (k += 1) {
        const o = obj(k);
        if (m.w(o + 6) == 0) continue;
        const rp = m.l(ad.ROW_PTR) -% B;
        const anim: u32 = if (k - 6 - b < 3) ad.A_FIRE_A else ad.A_FIRE_B;
        if (m.w(s + ad.S_VOLLEY) == 0) {
            m.setl(ad.ANIM_NEW, anim + B);
            m.setw(s + ad.S_INFACT, 5);
            m.setw(ad.ANIM_CHANGE, 1);
            m.setw(rp, m.w(o + 2) - 7);
            shooters += 1;
            u.animStep(g, o);
        }
        if (m.w(s + ad.S_VOLLEY) > 0x10 and m.w(s + ad.S_INFACT) == 5) m.setw(o + 4, mem.romW(anim));
        if (m.w(rp) == 0) continue;
        const bx = s16(m.w(o) + mem.muluW(m.w(s + ad.S_VOLLEY) + m.w(ad.MUZZLE), m.w(ad.DIR)));
        if (0 < bx and bx < 0x140) {
            g.plot(bx, m.w(rp));
            if (u.hitTest(g, bx, s16(m.w(rp) + 7), 3, 2)) m.setw(rp, 0);
        }
        m.setl(ad.ROW_PTR, m.l(ad.ROW_PTR) +% 2);
    }
    if (m.w(s + ad.S_VOLLEY) == 0 and shooters != 0) g.play(0x27 + shooters, 0x81);
    m.addw(s + ad.S_VOLLEY, 4);
    if (m.w(s + ad.S_VOLLEY) > 0x3C) m.setw(s + ad.S_VOLLEY, 0);
}

fn reformInf(g: *Game, s: u32) void { // $C534
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    if (m.w(s + ad.S_INFREF) == 0) return;
    if (m.w(s + ad.S_INFREF) == 1) {
        m.setl(ad.ANIM_NEW, ad.A_MARCH + @as(u32, g.rnd(2)) * 2 + B);
        m.setw(ad.ANIM_CHANGE, 1);
    }
    m.setw(s + ad.S_INFREF, u.reform(g, b + 6, obj(b + 6), 6, m.l(s + ad.S_INFFORM)));
}
