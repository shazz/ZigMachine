// --------------------------------------------------------------------------
// Cavalry ($CE4A; riders 3-5 of each side) with its helpers $C924 (step),
// $CA46 (riderless horse), $CB08 (bump), $CB96 (fall) and $CD28 (sabre).
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const u = @import("units.zig");
const inf = @import("infantry.zig");
const Game = @import("game.zig").Game;

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

fn setColumn(g: *Game, s: u32) void {
    if (g.m.l(s + ad.S_CAVFORM) != ad.T_COLUMN + B) {
        g.m.setw(s + ad.S_CAVREF, 1);
        g.m.setl(s + ad.S_CAVFORM, ad.T_COLUMN + B);
    }
}

/// Any live rider past `lim` in y (above when `up`) stops a vertical move.
fn yBlocked(g: *Game, base: u32, up: bool, lim: i32) bool {
    var k: u32 = 0;
    while (k < 3) : (k += 1) {
        const o = base + 12 * k;
        if (g.m.w(o + 6) == 0) continue;
        if (if (up) g.m.w(o + 2) < lim else g.m.w(o + 2) > lim) return true;
    }
    return false;
}

pub fn cavalry(g: *Game, s: u32) void { // $CE4A
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    m.setw(ad.ANIM_CHANGE, 0);
    var act = inf.cmdFor(g, s, 2) & 0x7F;
    if (m.w(s + ad.S_ENTER) & 2 != 0) {
        act = 0; // $CE80: entering riders ignore the command and creep in
    } else if (m.w(s + ad.S_RETREAT) & 2 != 0) {
        act = if (b != 0) 3 else 7;
    }
    const base = obj(b + 3);
    var horiz: i32 = 1;
    var dd: i32 = 0;
    switch (act) {
        3 => {
            dd = 1;
            if (b != 0) { // column only when riding BACKWARDS
                act = 7;
                setColumn(g, s);
            }
        },
        7 => {
            dd = -1;
            if (b != 0) {
                act = 3;
                if (m.w(ad.CF3E) != 0) m.setw(ad.CF3E, 0);
            } else setColumn(g, s);
        },
        5 => {
            horiz = 0;
            dd = if (yBlocked(g, base, false, 0xC4)) 0 else 2;
        },
        1 => {
            horiz = 0;
            dd = if (yBlocked(g, base, true, 0x0A)) 0 else -2;
        },
        else => act = 8,
    }
    act = s16(act) >> 1; // asr.w at $D032
    if (m.w(s + ad.S_RETREAT) & 2 != 0) {
        act = 0x0A;
        m.setw(s + ad.S_CAVHALT, 2);
    }
    if (m.w(s + ad.S_CAVHALT) == 1 and dd != 0) {
        m.addw(obj(m.w(s + ad.S_CAVLEAD)), m.w(ad.DIR));
        m.setw(s + ad.S_CAVHALT, 2);
    }
    if (noneAlive(g, b)) {
        if (!u.reinforce(g, 3)) m.setw(s + ad.S_ALIVE, m.w(s + ad.S_ALIVE) & 0xFFFD) else act = 3;
    }
    if (m.w(s + ad.S_CAVACT) != act or m.w(s + ad.S_CAVHALT) == 1) {
        if (m.w(s + ad.S_SABRE) == 0) {
            if (m.w(s + ad.S_CAVHALT) == 1) {
                m.setl(ad.ANIM_NEW, ad.A_CAV_HALT + B);
            } else {
                m.setl(ad.ANIM_NEW, @intCast(@as(i32, ad.A_CAV) + act * 10 + @as(i32, B)));
                if (act == 3) g.play(0x12, 0x81);
            }
            m.setw(s + ad.S_CAVACT, act);
            m.setw(ad.ANIM_CHANGE, 1);
        }
    }
    var k = b + 3;
    while (k < b + 6) : (k += 1) {
        const o = obj(k);
        step(g, o, s, horiz, dd, k);
        horse(g, o, s);
        bump(g, o, s, horiz, dd, k);
        fall(g, o, s);
        if (m.w(o + 6) != 0 and m.w(s + ad.S_SABRE) == 0) u.animStep(g, o);
    }
    sabre(g, s);
    if (m.w(s + ad.S_CAVREF) != 0 and m.w(s + ad.S_CAVHALT) != 1)
        m.setw(s + ad.S_CAVREF, u.reform(g, b + 3, obj(b + 3), 3, m.l(s + ad.S_CAVFORM)));
    const lx = m.w(obj(m.w(s + ad.S_CAVLEAD)));
    if ((b == 0 and lx == 0x28) or (b != 0 and lx == 0x10E)) {
        m.setw(s + ad.S_CAVHALT, 1);
        if (m.w(s + ad.S_ENTER) & 2 != 0) m.setw(s + ad.S_ENTER, m.w(s + ad.S_ENTER) & 0xFFFD);
    }
}

fn noneAlive(g: *Game, b: i32) bool {
    var k = b + 3;
    while (k < b + 6) : (k += 1) if (g.m.w(obj(k) + 6) != 0) return false;
    return true;
}

/// The cell under a rider: an obstacle bumps a human's rider, water drowns.
fn terrain(g: *Game, o: u32, s: u32, b: i32) void {
    const m = &g.m;
    const cell = u.gridAt(g, s16(m.w(o) - @divTrunc(b, 3)), m.w(o + 2));
    if (cell == 0) return;
    if (cell < 0x64 and m.w(s + ad.S_RETREAT) & 2 == 0 and m.w(s + ad.S_CPU) == 0) m.setw(o + 6, 0x64);
    if (cell == 0x64) m.setw(o + 6, 0x65);
}

fn step(g: *Game, o: u32, s: u32, horiz: i32, dd: i32, k: i32) void { // $C924
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    if (m.w(o + 6) != 0x0A) return;
    if (horiz == 1) {
        if (m.w(s + ad.S_CAVHALT) != 1) {
            if (m.w(s + ad.S_RETREAT) & 2 != 0) m.addw(o, dd - m.w(ad.DIR)) else m.addw(o, dd + m.w(ad.DIR));
        }
    } else {
        const v = s16(m.w(o + 2) + dd);
        u.drawMove(g, v, k);
        m.setw(o + 2, v);
    }
    if (m.w(o) > 0x17C) m.setw(o, -60);
    if (m.w(o) < -60) m.setw(o, 0x17C);
    if (0x28 < m.w(o) and m.w(o) < 0x10E) terrain(g, o, s, b);
    if (m.w(s + ad.S_RETREAT) & 2 != 0) {
        if ((b == 0 and m.w(o) < -45) or (b != 0 and m.w(o) > 0x159))
            m.setw(s + ad.S_ALIVE, m.w(s + ad.S_ALIVE) & 0xFFFD);
    }
}

fn horse(g: *Game, o: u32, s: u32) void { // $CA46: the riderless horse
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    if (m.w(o + 6) != 0x17) return;
    m.addw(o, m.w(ad.DIR));
    m.addw(o, m.w(ad.DIR));
    if (m.w(o) > 0x17C or m.w(o) < -60) {
        m.setw(o + 6, 0);
        m.setw(s + ad.S_CAVACT, 0x14);
        return;
    }
    if (u.gridAt(g, s16(m.w(o) - @divTrunc(b, 3)), m.w(o + 2)) == 0x64) {
        m.setw(o + 6, 0);
        m.setw(s + ad.S_INFACT, 0x14); // sic: +$14, the INFANTRY action, in the original
        g.play(0x12, 0x82);
        if (m.w(ad.FIELD) == 0) {
            g.blit(.log, .fx_b, 5, m.w(o), m.w(o + 2));
            g.play(0x11, 0x81);
        }
    }
}

fn bump(g: *Game, o: u32, s: u32, horiz: i32, dd: i32, k: i32) void { // $CB08
    const m = &g.m;
    const st = m.w(o + 6);
    if (st != 0x11 and st != 0x64) return;
    if (st == 0x64) {
        m.setw(o + 6, 0x11);
        m.setl(o + 8, ad.A_CAV_BUMP + B);
        if (horiz == 1) {
            m.setw(o, m.w(o) - s16(dd + m.w(ad.DIR)));
        } else {
            const v = s16(m.w(o + 2) - dd);
            u.drawMove(g, v, k);
            m.setw(o + 2, v);
        }
    }
    if (m.derefW(m.l(o + 8)) == -1) {
        m.setw(o + 6, 0x0A);
        m.setw(s + ad.S_CAVACT, 0x14);
    }
}

fn fall(g: *Game, o: u32, s: u32) void { // $CB96
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    const st = m.w(o + 6);
    if (st != 0x13 and st != 0x65) return;
    if (st == 0x65) {
        g.play(0x1C, 0x82);
        m.setw(o + 6, 0x13);
        m.setl(o + 8, ad.A_FALL + B);
    }
    if (m.derefW(m.l(o + 8)) != -1) return;
    if (u.gridAt(g, s16(m.w(o) - @divTrunc(b, 3)), m.w(o + 2)) == 0x64) {
        g.play(0x12, 0x82);
        if (m.w(ad.FIELD) == 0) {
            g.blit(.log, .fx_b, 5, m.w(o), m.w(o + 2));
            g.play(0x11, 0x81);
        }
        m.setw(o + 6, 0);
        m.setw(s + ad.S_CAVACT, 0x14);
    } else {
        g.blit(.bg, .cur, 5, m.w(o), m.w(o + 2));
        g.blit(.log, .cur, 5, m.w(o), m.w(o + 2));
        g.play(0x12, 0x81);
        m.setw(o + 6, 0x17);
        m.addw(o, 1);
        m.setl(o + 8, ad.A_HORSE + @as(u32, g.rnd(3)) * 2 + B);
    }
    var r: u32 = undefined;
    if (b != 0) {
        m.setw(ad.SIDE_B + ad.S_CAVLEAD, u.firstAlive(g, 0x0F, 0x12));
        r = m.l(ad.REC_B) -% B;
    } else {
        m.setw(ad.SIDE_A + ad.S_CAVLEAD, u.firstAlive(g, 3, 6));
        r = m.l(ad.REC_A) -% B;
    }
    m.setb(r + 2, m.b(r + 2) - 1);
}

fn sabre(g: *Game, s: u32) void { // $CD28
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    const v = if (m.w(s + ad.S_CAVHALT) != 1) inf.cmdFor(g, s, 2) else 0;
    if (v & 0x80 == 0 and m.w(s + ad.S_SABRE) == 0) return;
    if (m.w(s + ad.S_SABRE) == 0 and m.l(s + ad.S_CAVFORM) != ad.T_LINE_A + B) {
        m.setw(s + ad.S_CAVREF, 1);
        m.setl(s + ad.S_CAVFORM, ad.T_LINE_A + B);
    }
    m.setw(ad.MUZZLE, 6);
    var k = b + 3;
    while (k < b + 6) : (k += 1) {
        const o = obj(k);
        if (m.w(o + 6) != 0x0A) continue;
        if (m.w(s + ad.S_SABRE) == 0) {
            m.setl(ad.ANIM_NEW, ad.A_SABRE + B);
            m.setw(s + ad.S_CAVACT, v);
            m.setw(ad.ANIM_CHANGE, 1);
        }
        u.animStep(g, o);
        _ = u.hitTest(g, s16(m.w(o) + m.w(ad.MUZZLE)), s16(m.w(o + 2) - 2), 4, 5);
    }
    m.addw(s + ad.S_SABRE, 1);
    if (m.w(s + ad.S_SABRE) == 4) {
        m.setw(s + ad.S_SABRE, 0);
        m.setw(s + ad.S_CAVACT, 0x0C);
    }
}
