// --------------------------------------------------------------------------
// The battle's state (its RAM image, mem.zig, plus what the port keeps beside
// it) and the helpers every routine shares: the RNG $50DA, the blit / plot /
// hline wrappers that also count for the pacing model, play_seq $4CB6 and the
// unit switch $E202. One iteration of the loop is loop.zig; setup ($AAD0 up
// to the first iteration) is setup.zig.
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const A = @import("assets.zig");
const gfx = @import("gfx.zig");
const cost = @import("cost.zig");
const pacing = @import("pacing.zig");
const loop = @import("loop.zig");

const s16 = mem.s16;

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
            // An empty slot (w = 0) still touches the counter, with 0 bytes,
            // as the model's does (the touch order matters, see cost.zig);
            // `.?` would be unchecked in ReleaseSmall.
            const bytes: i64 = if (A.banks[@intFromEnum(id)].get(n)) |s| @as(i64, s.w / 16) * s.h * 8 else 0;
            c.add(.flip_bytes, bytes);
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

    /// One iteration of the battle loop (loop.zig). The sounds started are in events[].
    pub fn frame(self: *Game, inp: Inputs) void {
        loop.frame(self, inp);
    }

    /// The screen the last frame flipped to.
    pub fn shown(self: *Game) *[gfx.PIXELS]u8 {
        return self.screen(ad.PHYSICAL);
    }
};
