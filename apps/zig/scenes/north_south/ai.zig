// --------------------------------------------------------------------------
// The CPU side: plan choice $3E3E, command $3C8E and the script interpreter
// $3778 (one opcode per call, ten opcodes), targeting $3602 / $36E8.
// A slot is 8 bytes: state (1 idle, 2+ running), script pointer, plan
// (10 x target + own type).
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const Game = @import("game.zig").Game;

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

const LEAD = [3]u32{ ad.S_CANLEAD, ad.S_CAVLEAD, ad.S_INFLEAD };

fn dist(m: *const mem.Mem, a: u32, b: u32) i32 { // $35C2
    return s16(@as(i32, @intCast(@abs(s16(m.w(a) - m.w(b))))) + @as(i32, @intCast(@abs(s16(m.w(a + 2) - m.w(b + 2))))));
}

/// $3602: the nearest enemy leader (0 cannon, 1 cavalry, 2 infantry).
fn nearest(g: *Game, me: u32, enemy: u32) u32 {
    const m = &g.m;
    var t: u32 = 0;
    var best: i32 = 1000;
    if (m.w(enemy + ad.S_CANLEAD) != -1) best = dist(m, me, obj(m.w(enemy + ad.S_CANLEAD)));
    for ([_]u32{ 1, 2 }) |i| {
        if (m.w(enemy + LEAD[i]) != -1) {
            const d = dist(m, me, obj(m.w(enemy + LEAD[i])));
            if (d < best) {
                best = d;
                t = i;
            }
        }
    }
    return t;
}

/// $36E8: a target more than 200 px away in x is replaced by random(3).
fn farRandom(g: *Game, me: u32, enemy: u32, t: u32) u32 {
    const tgt = obj(g.m.w(enemy + LEAD[t]));
    if (@abs(s16(g.m.w(me) - g.m.w(tgt))) > 0xC8) return g.rnd(3);
    return t;
}

/// $3E3E: an idle slot starts a plan with probability 1/(10*(2-level)+1).
pub fn plan(g: *Game, s: u32, enemy: u32, typ: u32) void {
    const m = &g.m;
    const slot = m.l(ad.AI_SLOT_PTR) -% B;
    if (m.w(slot) != 1) return;
    const n: u32 = ((((@as(u32, @bitCast(2 - m.w(s + ad.S_LEVEL))) & 0xFFFF) * 10) + 1) & 0xFFFF);
    if (g.rnd(n) != 0) return;
    switch (typ) {
        0 => {
            const me = obj(m.w(s + ad.S_CANLEAD));
            const t = farRandom(g, me, enemy, nearest(g, me, enemy));
            m.setw(slot + 6, if (t == 0) 0 else if (t == 1) 10 else 20);
            m.setl(slot + 2, ad.AI_SCRIPT_CAN + B);
        },
        1, 2 => {
            const me = obj(m.w(s + LEAD[typ]));
            const t = nearest(g, me, enemy);
            m.setw(slot + 6, @intCast(typ + 10 * t));
            m.setl(slot + 2, (if (typ == 1) ad.AI_SCRIPT_CAV else ad.AI_SCRIPT_INF) + B);
            if (m.w(ad.BRIDGE_Y) == 0) m.setl(slot + 2, m.l(slot + 2) +% 6);
        },
        else => return,
    }
    m.setw(slot, 2);
}

/// $3C8E: the command of the unit whose slot is at AI_SLOT_PTR.
pub fn command(g: *Game, s: u32, enemy: u32) i32 {
    const m = &g.m;
    const slot = m.l(ad.AI_SLOT_PTR) -% B;
    if (m.w(slot) == 1) return 8;
    const pl = m.w(slot + 6);
    const own = @mod(pl, 10);
    const tgt = @divTrunc(pl, 10);
    // Plans are 10 x target + own, both 0..2; any other value reads
    // uninitialised locals in the original and never occurs.
    if (pl < 0 or own > 2 or tgt > 2) return 8;
    const mine = m.w(s + LEAD[@intCast(own)]);
    const theirs = m.w(enemy + LEAD[@intCast(tgt)]);
    const tx = m.w(obj(theirs));
    const mx = m.w(obj(mine));
    if (mine == -1 or !(0 <= tx and tx <= 0x13F) or theirs == -1 or !(0 <= mx and mx <= 0x13F)) {
        m.setw(slot, 1);
        return 8;
    }
    return script(g, s, obj(mine), obj(theirs), slot);
}

const Ctx = struct {
    g: *Game,
    slot: u32,
    mx: i32,
    my: i32,
    ex: i32,
    ey: i32,

    fn adv(self: Ctx, n: i32) void {
        const m = &self.g.m;
        m.setl(self.slot + 2, m.l(self.slot + 2) +% @as(u32, @bitCast(n)));
    }
    fn end(self: Ctx) void {
        self.g.m.setw(self.slot, 1);
    }
    fn alignEnemy(self: Ctx) i32 { // $394C
        if (self.ey <= self.my and self.my <= self.ey + 2) {
            self.adv(2);
            return 8;
        }
        if (self.my > self.ey + 2) return 1;
        if (self.my < self.ey) return 5;
        return 8;
    }
};

/// $3778: one opcode per call.
fn script(g: *Game, s: u32, me: u32, en: u32, slot: u32) i32 {
    const m = &g.m;
    g.cost.add(.ai_op, 1);
    const b = m.w(ad.SIDE_BASE) != 0;
    const op = m.derefW(m.l(slot + 2));
    const c = Ctx{ .g = g, .slot = slot, .mx = m.w(me), .my = m.w(me + 2), .ex = m.w(en), .ey = m.w(en + 2) };
    const mx = c.mx;
    const my = c.my;
    const ex = c.ex;
    const ey = c.ey;
    const by = m.w(ad.BRIDGE_Y);
    switch (op) {
        -1 => { // $3C3A
            if (m.w(slot) > 2) m.addw(slot, -1) else c.end();
            return 8;
        },
        0 => return c.alignEnemy(),
        8 => { // $39B8
            if (my == ey) {
                c.adv(2);
                return 8;
            }
            return if (my > ey) 1 else 5;
        },
        1 => return approach50(c, b),
        7 => return approach10(c, b),
        2 => { // $3BBE cannon: fire until the gauge covers the distance
            const p = m.w(s + ad.S_POWER);
            if (b) {
                if (s16(mx - s16(p + 16)) > ex) return 0x80;
            } else if (s16(mx + p + 8) < ex) return 0x80;
            c.end();
            return 8;
        },
        6 => { // $3C1E
            c.adv(2);
            m.setw(slot, 7);
            return 0x80;
        },
        else => {},
    }
    const across = (b and mx >= 0x64 and ex <= 0x64) or (!b and mx <= 0xE1 and ex >= 0xE1);
    switch (op) {
        3 => { // $381E align with the crossing line
            if (!across) {
                c.adv(4);
                return 8;
            }
            if (my > by + 1 or my < by - 1) return if (my > by) 1 else 5;
            c.adv(2);
            return 8;
        },
        4 => { // $38B4 cross on the line
            if (by - 1 <= my and my <= by + 1) {
                if (b) {
                    if (mx >= 0x64 and ex <= 0x64 and mx >= 0x64) return 7;
                } else if (mx <= 0xE1 and ex >= 0xE1 and my <= 0xE1) return 3; // sic: compares y
                c.adv(2);
                return 0x80;
            }
            c.adv(-2);
            return c.alignEnemy();
        },
        5 => { // $37B6
            if (b) {
                if (mx >= 0xE1 and ex <= 0x64) {
                    c.adv(2);
                    return 3;
                }
            } else if (mx <= 0x64 and ex >= 0xE1) {
                c.adv(2);
                return 7;
            }
            c.adv(6);
            return 8;
        },
        else => return 8,
    }
}

fn approach50(c: Ctx, b: bool) i32 { // $3A0A: get within 50 px in x
    const plan12 = c.g.m.w(c.slot + 6) == 12;
    if (b) {
        if (c.mx - 50 <= c.ex and c.mx >= c.ex + 8) {
            c.adv(2);
            return 8;
        }
        if (c.mx - 50 >= c.ex) return 7;
        if (plan12) c.end();
        return 3;
    }
    if (c.mx + 50 >= c.ex and c.mx <= c.ex - 4) {
        c.adv(2);
        return 8;
    }
    if (c.mx + 50 < c.ex) return 3;
    if (plan12) c.end();
    return 7;
}

fn approach10(c: Ctx, b: bool) i32 { // $3AE4: get within 10 px (melee)
    if (b) {
        if (c.mx - 10 <= c.ex and c.mx >= c.ex - 10) {
            c.adv(2);
            return 8;
        }
        if (c.mx - 10 > c.ex) return 7;
        if (c.mx + 10 < c.ex) c.end();
        return 8;
    }
    if (c.mx + 10 >= c.ex and c.mx < c.ex + 10) {
        c.adv(2);
        return 8;
    }
    if (c.mx + 10 < c.ex) return 3;
    if (c.mx - 10 > c.ex) c.end();
    return 8;
}
