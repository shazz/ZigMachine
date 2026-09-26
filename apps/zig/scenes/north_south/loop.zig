// --------------------------------------------------------------------------
// One iteration of ns.app's battle loop ($E4FE), in the original's order:
//   1. the background ($1C934) copied over the logical screen ($14BDA);
//   2. side A (the Union): stick or AI, Shift, Esc/Backspace, the rout rule,
//      then cannon, cavalry, infantry. Musket balls and shells are plotted as
//      they fly; corpses, craters and HUD icons are painted into the
//      background as they happen;
//   3. side B (the Confederates), the same;
//   4. the draw pass $B194 (on the river, 12 sparkle pixels and 12 RNG draws
//      first), the flip, the demo timer and the end test.
// The state and the helpers every routine shares are in game.zig.
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const A = @import("assets.zig");
const gfx = @import("gfx.zig");
const cost = @import("cost.zig");
const ai = @import("ai.zig");
const cannon = @import("cannon.zig");
const cavalry = @import("cavalry.zig");
const infantry = @import("infantry.zig");
const G = @import("game.zig");
const Game = G.Game;
const Inputs = G.Inputs;

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

fn readInput(g: *Game, player: i32, inp: Inputs) i32 { // $AD68
    const v: i32 = if (player == g.m.b(ad.CFG_JOYPLAYER) and g.cfg.mode == 0) inp.port1 else inp.joy;
    var d = mem.romB(ad.T_JOYDIR + @as(u32, @intCast(v & 0x7F)));
    if (v & 0x80 != 0) d |= 0x80;
    return s16(if (d & 0x80 != 0) d - 0x100 else d);
}

fn rout(g: *Game) i32 { // $E2FA: an outnumbered CPU side with no cannon runs
    const m = &g.m;
    const ra = m.l(ad.REC_A) -% B;
    const rb = m.l(ad.REC_B) -% B;
    if (m.w(ad.SIDE_BASE) != 0) {
        if (m.b(rb + 3) == 0 and ((m.b(rb + 1) + m.b(rb + 2)) * 3) & 0xFFFF < m.b(ra + 1) + m.b(ra + 2) + m.b(ra + 3)) return 12;
    } else if (m.b(ra + 3) == 0 and ((m.b(ra + 1) + m.b(ra + 2)) * 3) & 0xFFFF < m.b(rb + 1) + m.b(rb + 2) + m.b(rb + 3)) return 12;
    return 8;
}

fn sideTurn(g: *Game, s: u32, enemy: u32, player: i32, inp: Inputs, sw_key: i32, ret_key: i32) void {
    const m = &g.m;
    if (m.w(s + ad.S_CPU) == 0) {
        m.setw(ad.CMD, readInput(g, player, inp));
        if (inp.key == sw_key) g.switchUnit(s);
        if (inp.key == ret_key) m.setw(ad.CMD, 12);
    } else m.setw(ad.CMD, rout(g));
    if (m.w(ad.CMD) == 12) {
        const rec = m.l(if (s == ad.SIDE_A) ad.REC_A else ad.REC_B);
        if (rec != g.cfg.army_b or g.cfg.retreat_ok) m.setw(s + ad.S_RETREAT, 7);
        if (m.w(s + ad.S_ENTER) != 0) m.setw(s + ad.S_RETREAT, 0); // cancelled while entering
    }
    if (m.w(s + ad.S_SWITCH) != 0) m.addw(s + ad.S_SWITCH, -1);
    const Unit = struct { bit: i32, slot: u32, typ: u32, key: cost.Key };
    const units = [3]Unit{
        .{ .bit = 4, .slot = ad.S_AI_CAN, .typ = 0, .key = .u_cannon },
        .{ .bit = 2, .slot = ad.S_AI_CAV, .typ = 1, .key = .u_cavalry },
        .{ .bit = 1, .slot = ad.S_AI_INF, .typ = 2, .key = .u_infantry },
    };
    for (units) |un| {
        if (m.w(s + ad.S_ALIVE) & un.bit == 0) continue;
        g.cost.add(un.key, 1);
        if (m.w(s + ad.S_CPU) == 1) {
            g.cost.add(.ai, 1);
            m.setl(ad.AI_SLOT_PTR, s + un.slot + B);
            ai.plan(g, s, enemy, un.typ);
            if (m.w(s + ad.S_ENTER) & un.bit == 0) m.setw(ad.CMD, ai.command(g, s, enemy));
        }
        switch (un.typ) {
            0 => cannon.cannon(g, s),
            1 => cavalry.cavalry(g, s),
            else => infantry.infantry(g, s),
        }
    }
}

/// One iteration of the battle loop. The sounds started are in events[].
pub fn frame(g: *Game, inp: Inputs) void {
    const m = &g.m;
    g.nevents = 0;
    g.frames += 1;
    g.cost.reset();
    const logical = g.screen(ad.LOGICAL);
    const bg = g.screen(ad.BG);
    // $14BDA. Both resolve to the same buffer only after a miss (a bad
    // screen pointer), and @memcpy must not alias.
    if (logical != bg) @memcpy(logical, bg);
    m.setw(ad.SIDE_BASE, 0);
    m.setw(ad.DIR, 1);
    m.setl(ad.BANK_CUR, m.l(ad.BANK_UNION));
    sideTurn(g, ad.SIDE_A, ad.SIDE_B, 1, inp, g.keys[0], g.keys[2]);
    m.setw(ad.SIDE_BASE, 12);
    m.setw(ad.DIR, -1);
    m.setl(ad.BANK_CUR, m.l(ad.BANK_CONFED));
    sideTurn(g, ad.SIDE_B, ad.SIDE_A, 2, inp, g.keys[1], g.keys[3]);
    draw(g);
    g.pace.frameDone(g.field, &g.cost); // trap #5
    const lg = m.l(ad.LOGICAL);
    m.setl(ad.LOGICAL, m.l(ad.PHYSICAL));
    m.setl(ad.PHYSICAL, lg);
    if (g.cfg.mode == 3) demoTimer(g, inp);
    if (m.w(ad.SIDE_A + ad.S_ALIVE) == 0 or m.w(ad.SIDE_B + ad.S_ALIVE) == 0) finish(g);
}

fn demoTimer(g: *Game, inp: Inputs) void {
    const m = &g.m;
    var fire = inp.key == 1;
    if (!fire) {
        const t = m.w(ad.DEMO_TIMER);
        m.addw(ad.DEMO_TIMER, -1);
        fire = t == 0;
    }
    if (!fire) return;
    const a = g.rnd(2) != 0;
    m.setw((if (a) ad.SIDE_A else ad.SIDE_B) + ad.S_ALIVE, 0);
    const r = m.l(if (a) ad.REC_A else ad.REC_B) -% B;
    for ([_]u32{ 3, 2, 1 }) |i| m.setb(r + i, 0);
}

fn finish(g: *Game) void { // after the loop, $EA2E
    const m = &g.m;
    const a2 = g.cfg.army_a;
    if (m.w(ad.SIDE_A + ad.S_ALIVE) == 0 and m.l(ad.REC_A) == a2) {
        m.setb(m.l(ad.REC_A) -% B + 3, 0);
        g.result = 2;
    } else if (m.w(ad.SIDE_B + ad.S_ALIVE) == 0 and m.l(ad.REC_B) == a2) {
        m.setb(m.l(ad.REC_B) -% B + 3, 0);
        g.result = 2;
    } else {
        m.setb(g.cfg.army_b -% B + 3, 0);
        g.result = 1;
    }
}

fn draw(g: *Game) void { // $B194 (+ $B124, the river sparkle)
    const m = &g.m;
    if (m.w(ad.FIELD) == 0) {
        var i: u32 = 0;
        while (i < 12) : (i += 1) {
            g.pen = @intCast(mem.romB(ad.T_SPARKLE_COL + g.rnd(3)));
            g.plot(mem.romW(ad.T_SPARKLE_XY + 4 * i + 2), mem.romW(ad.T_SPARKLE_XY + 4 * i));
        }
        g.pen = 0;
    }
    const scr = g.screen(ad.LOGICAL);
    var p: u32 = ad.DRAW;
    while (p < mem.HI) : (p += 1) { // ends at the y >= 200 sentinel; see units.hitTest
        const k = m.b(p);
        const o = obj(k);
        g.cost.add(.draw_it, 1);
        if (m.w(o + 2) >= 0xC8) break;
        if (m.w(o + 6) == 0) continue;
        const id: A.BankId = if (k >= 24) .decor else if (k >= 12) .confed else .union_;
        g.tallyBlit(id, m.w(o + 4), gfx.blit(scr, id, m.w(o + 4), m.w(o), m.w(o + 2)));
    } else mem.misses += 1;
}
