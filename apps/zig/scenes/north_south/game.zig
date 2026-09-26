// --------------------------------------------------------------------------
// The battle: one iteration of ns.app's loop ($E4FE) per call to frame(), in
// the original's order —
//   1. the background ($1C934) copied over the logical screen ($14BDA);
//   2. side A (the Union): stick or AI, Shift, Esc/Backspace, the rout rule,
//      then cannon, cavalry, infantry. Musket balls and shells are plotted as
//      they fly; corpses, craters and HUD icons are painted into the
//      background as they happen;
//   3. side B (the Confederates), the same;
//   4. the draw pass $B194 (on the river, 12 sparkle pixels and 12 RNG draws
//      first), the flip, the demo timer and the end test.
// Setup ($AAD0 up to the first iteration) is in setup.zig.
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const A = @import("assets.zig");
const gfx = @import("gfx.zig");
const cost = @import("cost.zig");
const pacing = @import("pacing.zig");
const ai = @import("ai.zig");
const cannon = @import("cannon.zig");
const cavalry = @import("cavalry.zig");
const infantry = @import("infantry.zig");

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

/// The three bytes the game reads each frame: the last key scancode ($191C2,
/// 0 = none), the merged keyboard/port stick ($191CA) and the port-1 stick
/// ($191CE). Stick: bit0 up, bit1 down, bit2 left, bit3 right, bit7 fire.
pub const Inputs = struct { key: u8 = 0, joy: u8 = 0, port1: u8 = 0 };

pub const Where = enum { log, bg };
pub const BankSel = enum { decor, fx_a, fx_b, fx_c, cur };

pub const Cfg = struct {
    mode: u8, // $17362: bit0 Union CPU, bit1 Confederates CPU (3 = demo)
    level_a: i32,
    level_b: i32,
    /// The map's answer ($2240) to the defender's retreat request: out of scope
    /// here, and 1 in the reference dump.
    retreat_ok: bool,
    army_a: u32, // do_battle's arguments: the attacker's and defender's records
    army_b: u32,
};

pub const MAX_EVENTS = 32;

pub const Game = struct {
    m: mem.Mem,
    cfg: Cfg,
    keys: [4]i32, // switch A, switch B, retreat A, retreat B (scancodes)
    pen: u8,
    result: u8, // 0 while the battle runs, then 1 (armyA won) or 2 (armyB)
    frames: u32, // battle-loop iterations so far
    events: [MAX_EVENTS]u16, // sound sequences started this frame, in call order
    nevents: usize,
    field: usize,
    palette: [16]u16,
    cost: cost.Cost,
    /// Which way each bank sprite currently faces in RAM (the 68000 mirrors it
    /// in place on demand); pacing only.
    orient: [A.NBANKS][64]bool,
    pace: pacing.Pacer,

    // ------------------------------------------------------------ helpers
    pub fn rnd(self: *Game, n: u32) u32 { // $50DA
        self.cost.add(.rnd, 1);
        var s = self.m.l(ad.RNG);
        s = s *% 0x41C64E6D +% (s >> 20) +% 0x3039;
        self.m.setl(ad.RNG, s);
        const d = n & 0xFFFF;
        if (d == 0) {
            mem.misses += 1; // a division by zero in the original: never on any path
            return 0;
        }
        return (s >> 16) % d;
    }

    pub fn screen(self: *Game, addr: u32) *[gfx.PIXELS]u8 {
        return gfx.screenAt(self.m.l(addr)) orelse {
            mem.misses += 1;
            return &gfx.screens[0];
        };
    }

    fn bankId(self: *Game, sel: BankSel) A.BankId {
        return switch (sel) {
            .decor => .decor,
            .fx_a => .fx_a,
            .fx_b => .fx_b,
            .fx_c => .fx_c,
            .cur => if (self.m.l(ad.BANK_CUR) == self.m.l(ad.BANK_UNION)) .union_ else .confed,
        };
    }

    pub fn blit(self: *Game, where: Where, sel: BankSel, fr: i32, x: i32, y: i32) void {
        const id = self.bankId(sel);
        const scr = self.screen(if (where == .log) ad.LOGICAL else ad.BG);
        self.tallyBlit(id, fr, gfx.blit(scr, id, fr, s16(x), s16(y)));
    }

    /// Counts for the pacing model (pacing.zig); no effect on the game.
    pub fn tallyBlit(self: *Game, id: A.BankId, fr: i32, bc: ?gfx.BlitCost) void {
        const c = &self.cost;
        c.add(.blits, 1);
        const n: usize = @intCast(fr & 0x3FFF);
        const flip = fr & 0x8000 != 0;
        const o = &self.orient[@intFromEnum(id)][n & 63];
        if (n < 64 and o.* != flip) {
            o.* = flip;
            const s = A.banks[@intFromEnum(id)].get(n).?;
            c.add(.flip_bytes, @as(i64, s.w / 16) * s.h * 8);
        }
        const k = bc orelse return;
        const rw: i64 = @as(i64, k.rows) * k.words;
        const one = k.words == 1;
        const key: cost.Key = if (k.sh == 0) (if (one) .rw_a1 else .rw_an) else if (k.sh < 7) (if (one) .rw_l1 else .rw_ln) else (if (one) .rw_r1 else .rw_rn);
        c.add(.rows, k.rows);
        c.add(key, rw);
        c.add(.rw_sh, rw * (if (k.sh < 7) k.sh else 16 - k.sh));
        if (k.clipped) {
            c.add(.clip_blits, 1);
            c.add(.clip_rows, k.rows);
        }
    }

    pub fn plot(self: *Game, x: i32, y: i32) void {
        self.cost.add(.plots, 1);
        gfx.plot(self.screen(ad.LOGICAL), s16(x), s16(y), self.pen);
    }

    pub fn hline(self: *Game, x0: i32, y: i32, x1: i32, colour: u8) void {
        self.cost.add(.hlines, 1);
        self.cost.add(.hl_px, @as(i64, @abs(s16(x1) - s16(x0))) + 1);
        gfx.hline(self.screen(ad.LOGICAL), s16(x0), s16(y), s16(x1), colour);
    }

    pub fn play(self: *Game, n: u16, flags: u16) void { // $4CB6
        self.cost.add(.play, 1);
        if (self.nevents < MAX_EVENTS) {
            self.events[self.nevents] = n;
            self.nevents += 1;
        }
        self.pace.play(&self.cost, n, flags); // the player acts on the pacing clock
    }

    /// $E202: cycle the selected type 1 -> 4 -> 2 -> 1, skipping dead ones.
    pub fn switchUnit(self: *Game, s: u32) void {
        self.switchDepth(s, 0);
    }
    fn switchDepth(self: *Game, s: u32, depth: u32) void {
        const m = &self.m;
        if (m.w(s + ad.S_SWITCH) != 0) return;
        self.play(0x1E, 0x88);
        const sel = m.w(s + ad.S_SEL);
        const next: ?[3]i32 = switch (sel) {
            1 => .{ 4, 4, 0x18 },
            4 => .{ 2, 2, 0x1A },
            2 => .{ 1, 1, 0x19 },
            else => null,
        };
        if (next) |nx| {
            m.setw(s + ad.S_SEL, nx[0]);
            if (m.w(s + ad.S_ALIVE) & nx[1] != 0) {
                self.blit(.bg, .decor, nx[2], m.w(s + ad.S_HUDX), 0x13);
            } else if (depth < 3) { // with nothing alive the original recurses forever
                self.switchDepth(s, depth + 1);
            }
        }
        m.setw(s + ad.S_SWITCH, 5);
    }

    // ------------------------------------------------------------ one frame
    fn readInput(self: *Game, player: i32, inp: Inputs) i32 { // $AD68
        const v: i32 = if (player == self.m.b(ad.CFG_JOYPLAYER) and self.cfg.mode == 0) inp.port1 else inp.joy;
        var d = mem.romB(ad.T_JOYDIR + @as(u32, @intCast(v & 0x7F)));
        if (v & 0x80 != 0) d |= 0x80;
        return s16(if (d & 0x80 != 0) d - 0x100 else d);
    }

    fn rout(self: *Game) i32 { // $E2FA: an outnumbered CPU side with no cannon runs
        const m = &self.m;
        const ra = m.l(ad.REC_A) -% B;
        const rb = m.l(ad.REC_B) -% B;
        if (m.w(ad.SIDE_BASE) != 0) {
            if (m.b(rb + 3) == 0 and ((m.b(rb + 1) + m.b(rb + 2)) * 3) & 0xFFFF < m.b(ra + 1) + m.b(ra + 2) + m.b(ra + 3)) return 12;
        } else if (m.b(ra + 3) == 0 and ((m.b(ra + 1) + m.b(ra + 2)) * 3) & 0xFFFF < m.b(rb + 1) + m.b(rb + 2) + m.b(rb + 3)) return 12;
        return 8;
    }

    fn sideTurn(self: *Game, s: u32, enemy: u32, player: i32, inp: Inputs, sw_key: i32, ret_key: i32) void {
        const m = &self.m;
        if (m.w(s + ad.S_CPU) == 0) {
            m.setw(ad.CMD, self.readInput(player, inp));
            if (inp.key == sw_key) self.switchUnit(s);
            if (inp.key == ret_key) m.setw(ad.CMD, 12);
        } else m.setw(ad.CMD, self.rout());
        if (m.w(ad.CMD) == 12) {
            const rec = m.l(if (s == ad.SIDE_A) ad.REC_A else ad.REC_B);
            if (rec != self.cfg.army_b or self.cfg.retreat_ok) m.setw(s + ad.S_RETREAT, 7);
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
            self.cost.add(un.key, 1);
            if (m.w(s + ad.S_CPU) == 1) {
                self.cost.add(.ai, 1);
                m.setl(ad.AI_SLOT_PTR, s + un.slot + B);
                ai.plan(self, s, enemy, un.typ);
                if (m.w(s + ad.S_ENTER) & un.bit == 0) m.setw(ad.CMD, ai.command(self, s, enemy));
            }
            switch (un.typ) {
                0 => cannon.cannon(self, s),
                1 => cavalry.cavalry(self, s),
                else => infantry.infantry(self, s),
            }
        }
    }

    /// One iteration of the battle loop. The sounds started are in events[].
    pub fn frame(self: *Game, inp: Inputs) void {
        const m = &self.m;
        self.nevents = 0;
        self.frames += 1;
        self.cost.reset();
        @memcpy(self.screen(ad.LOGICAL), self.screen(ad.BG)); // $14BDA
        m.setw(ad.SIDE_BASE, 0);
        m.setw(ad.DIR, 1);
        m.setl(ad.BANK_CUR, m.l(ad.BANK_UNION));
        self.sideTurn(ad.SIDE_A, ad.SIDE_B, 1, inp, self.keys[0], self.keys[2]);
        m.setw(ad.SIDE_BASE, 12);
        m.setw(ad.DIR, -1);
        m.setl(ad.BANK_CUR, m.l(ad.BANK_CONFED));
        self.sideTurn(ad.SIDE_B, ad.SIDE_A, 2, inp, self.keys[1], self.keys[3]);
        self.draw();
        self.pace.frameDone(self.field, &self.cost); // trap #5
        const lg = m.l(ad.LOGICAL);
        m.setl(ad.LOGICAL, m.l(ad.PHYSICAL));
        m.setl(ad.PHYSICAL, lg);
        if (self.cfg.mode == 3) self.demoTimer(inp);
        if (m.w(ad.SIDE_A + ad.S_ALIVE) == 0 or m.w(ad.SIDE_B + ad.S_ALIVE) == 0) self.finish();
    }

    fn demoTimer(self: *Game, inp: Inputs) void {
        const m = &self.m;
        var fire = inp.key == 1;
        if (!fire) {
            const t = m.w(ad.DEMO_TIMER);
            m.addw(ad.DEMO_TIMER, -1);
            fire = t == 0;
        }
        if (!fire) return;
        const a = self.rnd(2) != 0;
        m.setw((if (a) ad.SIDE_A else ad.SIDE_B) + ad.S_ALIVE, 0);
        const r = m.l(if (a) ad.REC_A else ad.REC_B) -% B;
        for ([_]u32{ 3, 2, 1 }) |i| m.setb(r + i, 0);
    }

    fn finish(self: *Game) void { // after the loop, $EA2E
        const m = &self.m;
        const a2 = self.cfg.army_a;
        if (m.w(ad.SIDE_A + ad.S_ALIVE) == 0 and m.l(ad.REC_A) == a2) {
            m.setb(m.l(ad.REC_A) -% B + 3, 0);
            self.result = 2;
        } else if (m.w(ad.SIDE_B + ad.S_ALIVE) == 0 and m.l(ad.REC_B) == a2) {
            m.setb(m.l(ad.REC_B) -% B + 3, 0);
            self.result = 2;
        } else {
            m.setb(self.cfg.army_b -% B + 3, 0);
            self.result = 1;
        }
    }

    fn draw(self: *Game) void { // $B194 (+ $B124, the river sparkle)
        const m = &self.m;
        if (m.w(ad.FIELD) == 0) {
            var i: u32 = 0;
            while (i < 12) : (i += 1) {
                self.pen = @intCast(mem.romB(ad.T_SPARKLE_COL + self.rnd(3)));
                self.plot(mem.romW(ad.T_SPARKLE_XY + 4 * i + 2), mem.romW(ad.T_SPARKLE_XY + 4 * i));
            }
            self.pen = 0;
        }
        const scr = self.screen(ad.LOGICAL);
        var p: u32 = ad.DRAW;
        while (true) : (p += 1) {
            const k = m.b(p);
            const o = obj(k);
            self.cost.add(.draw_it, 1);
            if (m.w(o + 2) >= 0xC8) break;
            if (m.w(o + 6) == 0) continue;
            const id: A.BankId = if (k >= 24) .decor else if (k >= 12) .confed else .union_;
            self.tallyBlit(id, m.w(o + 4), gfx.blit(scr, id, m.w(o + 4), m.w(o), m.w(o + 2)));
        }
    }

    /// The screen the last frame flipped to.
    pub fn shown(self: *Game) *[gfx.PIXELS]u8 {
        return self.screen(ad.PHYSICAL);
    }
};
