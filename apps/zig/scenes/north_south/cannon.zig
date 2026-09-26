// --------------------------------------------------------------------------
// Cannon ($BAE2; slots 0-2 of each side), the power gauge $B936, the shell's
// flight $B30C, the burst and the bridge $B412, and $B2A4 (cells to water).
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const u = @import("units.zig");
const Game = @import("game.zig").Game;

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

fn commanded(g: *Game, s: u32) bool {
    return g.m.w(s + ad.S_SEL) == 4 or g.m.w(s + ad.S_CPU) == 1;
}

pub fn cannon(g: *Game, s: u32) void { // $BAE2
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    const base = obj(b);
    m.setw(ad.ANIM_CHANGE, 0);
    var act: i32 = if (commanded(g, s)) m.w(ad.CMD) & 0x7F else 0;
    if (m.w(s + ad.S_ENTER) & 4 != 0) {
        act = 0x19;
    } else if (m.w(s + ad.S_RETREAT) & 4 != 0) {
        act = 0x0A;
    }
    var dd: i32 = 0;
    if (act == 5 or act == 1) { // down / up
        dd = if (act == 5) 2 else -2;
        var k: u32 = 0;
        while (k < 3) : (k += 1) {
            const o = base + 12 * k;
            if (m.w(o + 6) != 0 and ((act == 5 and m.w(o + 2) > 0xC4) or (act == 1 and m.w(o + 2) < 0x0A))) dd = 0;
        }
        act = if (m.w(s + ad.S_CANACT) != 0) 5 else 6;
    } else if (act == 0x19) {
        act = 1;
        dd = 1;
    } else if (act == 0x0A) {
        act = 1;
        dd = -1;
    } else if (commanded(g, s)) {
        const dist = m.w(s + ad.S_DIST);
        if (dist > 0x28 or dist == 0) {
            act = if (m.w(s + ad.S_CANACT) == 5) 7 else 0;
        } else if (dist >= 0x0A) act = 4;
    }
    if (m.w(s + ad.S_CANACT) != act) {
        m.setl(ad.ANIM_NEW, @intCast(@as(i32, ad.A_CAN) + act * 10 + @as(i32, B)));
        m.setw(s + ad.S_CANACT, act);
        m.setw(ad.ANIM_CHANGE, 1);
    }
    var k = b;
    while (k < b + 3) : (k += 1) {
        const o = obj(k);
        if (m.w(o + 6) == 0x1B) move(g, s, o, k, b, dd);
        const st = m.w(o + 6);
        if (st == 0x65 or st == 0x1D) dying(g, s, o, b, st);
        if (m.w(o + 6) != 0) u.animStep(g, o);
    }
    gauge(g, s);
}

fn move(g: *Game, s: u32, o: u32, k: i32, b: i32, dd: i32) void {
    const m = &g.m;
    if (m.w(s + ad.S_ENTER) & 4 != 0 or m.w(s + ad.S_RETREAT) & 4 != 0) {
        m.addw(o, mem.muluW(dd, m.w(ad.DIR)));
    } else {
        const v = s16(m.w(o + 2) + dd);
        u.drawMove(g, v, k);
        m.setw(o + 2, v);
    }
    if (m.w(s + ad.S_ENTER) & 4 != 0) {
        if ((b == 0 and m.w(o) == 8) or (b != 0 and m.w(o) == 0x118))
            m.setw(s + ad.S_ENTER, m.w(s + ad.S_ENTER) & 0xFFFB);
    }
    if (m.w(s + ad.S_RETREAT) & 4 != 0) {
        if ((b == 0 and m.w(o) < -35) or (b != 0 and m.w(o) > 0x14F)) {
            m.setw(s + ad.S_ALIVE, m.w(s + ad.S_ALIVE) & 0xFFFB);
            m.setw(s + ad.S_RETREAT, m.w(s + ad.S_RETREAT) & 0xFFFB);
            m.setw(o + 6, 0);
            m.setw(s + ad.S_CANLEAD, -1);
        }
    }
}

fn dying(g: *Game, s: u32, o: u32, b: i32, st: i32) void {
    const m = &g.m;
    if (st == 0x65) {
        m.setw(o + 6, 0x1D);
        const blast = if (b != 0) m.w(ad.SIDE_A + ad.S_BLAST) else m.w(ad.SIDE_B + ad.S_BLAST);
        if (blast != 0) {
            m.setl(o + 8, ad.A_CAN_DIE_BLAST + B);
        } else {
            g.play(0x1C, 0x82);
            m.setl(o + 8, ad.A_CAN_DIE + B);
        }
        return;
    }
    const fr = m.w(o + 4);
    if (fr != 0x1F and fr != 0x21) return;
    g.blit(.bg, .cur, fr, m.w(o), m.w(o + 2));
    g.blit(.log, .cur, fr, m.w(o), m.w(o + 2));
    m.setw(o + 6, 0);
    var r: u32 = undefined;
    if (b != 0) {
        m.setw(s + ad.S_CANLEAD, u.firstAlive(g, 0x0C, 0x0F));
        r = m.l(ad.REC_B) -% B;
    } else {
        m.setw(s + ad.S_CANLEAD, u.firstAlive(g, 0, 3));
        r = m.l(ad.REC_A) -% B;
    }
    m.setb(r + 3, m.b(r + 3) - 1);
    if (m.w(s + ad.S_CANLEAD) == -1) m.setw(s + ad.S_ALIVE, m.w(s + ad.S_ALIVE) & 0xFFFB);
}

fn gauge(g: *Game, s: u32) void { // $B936: the red bar at the top
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    const v: i32 = if (commanded(g, s)) m.w(ad.CMD) else 0;
    if (v & 0x80 != 0 and m.w(s + ad.S_AMMO) != 0 and m.w(s + ad.S_DIST) == 0) {
        if (m.w(s + ad.S_POWER) < 0x118) m.addw(s + ad.S_POWER, 8) else m.setw(s + ad.S_POWER, 8);
        const p4 = @divTrunc(m.w(s + ad.S_POWER), 4);
        if (b != 0) {
            g.hline(0xE1, 3, 0x127, 0);
            g.hline(0xE1, 4, 0x127, 0);
            g.hline(0x127, 3, 0x127 - p4, 2);
            g.hline(0x127, 4, 0x127 - p4, 2);
        } else {
            g.hline(0x19, 3, 0x5F, 0);
            g.hline(0x19, 4, 0x5F, 0);
            g.hline(0x19, 3, p4 + 0x19, 2);
            g.hline(0x19, 4, p4 + 0x19, 2);
        }
    } else if (m.w(s + ad.S_POWER) > 8) {
        if (m.w(s + ad.S_DIST) < m.w(s + ad.S_POWER)) flight(g, s) else burst(g, s);
    }
}

fn flight(g: *Game, s: u32) void { // $B30C
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    m.setl(ad.ROW_PTR, s + ad.S_SHELLS + B);
    var k = b;
    while (k < b + 3) : (k += 1) {
        const o = obj(k);
        if (m.w(o + 6) == 0) continue;
        const rp = m.l(ad.ROW_PTR) -% B;
        if (m.w(s + ad.S_DIST) < 0x28 and m.w(s + ad.S_DIST) == 0) {
            g.play(0x0C, 0x81);
            m.setw(rp, m.w(o + 2) - 9);
        }
        g.plot(s16(m.w(o) + mem.muluW(m.w(s + ad.S_DIST) + 0x0B, m.w(ad.DIR))), m.w(rp));
        g.plot(s16(m.w(o) + mem.muluW(m.w(s + ad.S_DIST) + 0x0C, m.w(ad.DIR))), m.w(rp));
        m.setl(ad.ROW_PTR, m.l(ad.ROW_PTR) +% 2);
    }
    m.addw(s + ad.S_DIST, 0x0A);
    m.addw(ad.SHOT_X, 0x0A);
    m.setw(s + ad.S_BLAST, 4);
}

fn burst(g: *Game, s: u32) void { // $B412
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE);
    if (m.w(s + ad.S_BLAST) == 4) {
        m.setl(s + ad.S_BLASTANIM, ad.A_BLAST + @as(u32, g.rnd(4)) * 10 + B);
        m.addw(s + ad.S_AMMO, -1);
        if (m.w(s + ad.S_AMMO) == 0) {
            m.setw(s + ad.S_RETREAT, m.w(s + ad.S_RETREAT) | 4);
            m.setw(s + ad.S_CANACT, 8);
            if (m.w(s + ad.S_CPU) == 0) {
                m.setw(s + ad.S_SEL, 4);
                m.setw(s + ad.S_SWITCH, 0);
                g.switchUnit(s);
            }
        }
    }
    m.setl(ad.ROW_PTR, s + ad.S_SHELLS + B);
    var k = b;
    while (k < b + 3) : (k += 1) {
        const o = obj(k);
        if (m.w(o + 6) == 0) continue;
        const rp = m.l(ad.ROW_PTR) -% B;
        m.setw(ad.SHOT_X, m.w(o) + mem.muluW(m.w(s + ad.S_DIST) + 8, m.w(ad.DIR)));
        if (m.w(s + ad.S_BLAST) == 4) {
            m.addw(rp, @intCast(g.rnd(8)));
            m.addw(rp, -@as(i32, @intCast(g.rnd(4))));
            m.addw(rp, 3);
            _ = u.hitTest(g, s16(m.w(ad.SHOT_X) + 8), s16(m.w(rp) - 4), 0x0C, 0x0C);
            g.play(0x0E, 0x82);
        }
        const cell = if (m.w(ad.SHOT_X) < 0x87) u.gridAt(g, s16(m.w(ad.SHOT_X) + 5), m.w(rp)) else u.gridAt(g, m.w(ad.SHOT_X), m.w(rp));
        const fr = m.derefW(m.l(s + ad.S_BLASTANIM));
        if (cell == 0x64 or cell == 0x66) {
            g.blit(.log, .fx_b, fr, m.w(ad.SHOT_X), m.w(rp));
            if (m.w(ad.FIELD) == 0) g.play(0x11, 0x81);
        } else {
            g.blit(.log, .fx_c, fr, m.w(ad.SHOT_X), m.w(rp));
            g.blit(.log, .fx_a, fr, m.w(ad.SHOT_X), m.w(rp));
            m.setl(ad.ROW_PTR, m.l(ad.ROW_PTR) +% 2);
        }
    }
    m.setl(s + ad.S_BLASTANIM, m.l(s + ad.S_BLASTANIM) +% 2);
    m.addw(s + ad.S_BLAST, -1);
    if (m.w(s + ad.S_BLAST) != 1) return;
    landed(g, s, b);
    m.setw(s + ad.S_BLAST, 0);
    m.setw(s + ad.S_POWER, 8);
    m.setw(s + ad.S_DIST, 0);
}

/// The burst's last frame: the cell at x + 5*dir decides — the bridge, a
/// crater painted into the background, or nothing (water).
fn landed(g: *Game, s: u32, b: i32) void {
    const m = &g.m;
    m.setl(ad.ROW_PTR, s + ad.S_SHELLS + B);
    const fld = m.w(ad.FIELD);
    var k = b;
    while (k < b + 3) : (k += 1) {
        const o = obj(k);
        if (m.w(o + 6) == 0) continue;
        const rp = m.l(ad.ROW_PTR) -% B;
        m.setw(ad.SHOT_X, m.w(o) + mem.muluW(m.w(s + ad.S_DIST) + 8, m.w(ad.DIR)));
        const cell = u.gridAt(g, s16(mem.muluW(m.w(ad.DIR), 5) + m.w(ad.SHOT_X)), m.w(rp));
        if (cell == 0x65 or cell == 0x28) {
            if (fld == 0) g.blit(.bg, .decor, 0x1B, 0x90, 0x5C) else g.blit(.bg, .decor, 0x1C, 0x8E, 0x5F);
            if (m.w(ad.BRIDGE_HITS) == 0) {
                water(g, 0x15, fld + 0x12, 0x16, fld + 0x12);
                g.blit(.bg, .decor, 0x16, 0x90, fld * 5 + 0x5A);
                m.setw(ad.BRIDGE_HITS, 1);
            } else if (m.w(ad.BRIDGE_HITS) == 1) {
                water(g, 0x15, fld + 0x10, 0x16, fld + 0x14);
                g.blit(.bg, .decor, 0x17, 0x90, fld * 5 + 0x5A);
                m.setw(ad.BRIDGE_Y, if (fld == 0) 0x0A else 0xB8);
                m.setw(obj(m.w(ad.RAIL_OBJ)) + 6, 0);
            }
        } else if (cell != 0x64 and cell != 0x66) {
            const fr: i32 = @intCast(g.rnd(3));
            g.blit(.bg, .fx_c, fr, m.w(ad.SHOT_X), m.w(rp));
            m.setl(ad.ROW_PTR, m.l(ad.ROW_PTR) +% 2);
            if (cell != 0 and cell < 0x64) {
                const d = obj(cell) + 4;
                const wrecks = [_][2]i32{ .{ 2, 5 }, .{ 4, 6 }, .{ 0x0B, 0x0C } };
                for (wrecks) |e| if (m.w(d) == e[0]) m.setw(d, e[1]);
            }
        }
    }
}

fn water(g: *Game, x0: i32, y0: i32, x1: i32, y1: i32) void { // $B2A4
    var c = x0;
    while (c <= x1) : (c += 1) {
        var r = y0;
        while (r <= y1) : (r += 1) g.m.setb(@intCast(@as(i32, ad.GRID) + c * 50 + r), 0x64);
    }
}
