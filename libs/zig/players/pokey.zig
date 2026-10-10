// --------------------------------------------------------------------------
// The Atari POKEY (C012294), its AUDIO half only, one machine cycle at a time.
// The reference model for fpga/rtl/audio/zm_pokey.v, which must match it bit
// for bit (fpga/tests/test_rtl_pokey.py); pokey_test.zig checks the documented
// behaviour. Written from public documentation only:
//   - Altirra Hardware Reference Manual (Avery Lee), "POKEY" chapter: the
//     register map, the AUDCTL bits, the distortion selection, the 1.79 MHz
//     period formulas (N+4 single, N+7 joined) and the init-mode reset;
//   - Atari's POKEY data sheet (C012294) and De Re Atari ch. 7: the 64 / 15 kHz
//     bases (machine clock / 28, / 114), the high-pass filter, volume-only.
// No MAME, ASAP or GPL HDL source was read or ported.
//
// Not modelled: IRQs, serial, keyboard, pots, RANDOM, two-tone; only audio.
// The analog mixer (non-linear on the chip) is the plain sum of the levels.
//
// One `step()` is one machine cycle (NTSC 315/176 MHz = 1789772.7 Hz): init
// clears the polys and bases; the channels count and the high-pass latches
// latch, all seeing the state before the cycle; the polys shift. A `write()`
// lands between two cycles.
// --------------------------------------------------------------------------

pub const CLOCK_NUM: u64 = 315_000_000; // the NTSC machine clock is CLOCK_NUM / CLOCK_DEN Hz
pub const CLOCK_DEN: u64 = 176;

pub const AUDF1 = 0x0; // AUDFn = 2(n-1), AUDCn = 2(n-1)+1
pub const AUDC1 = 0x1;
pub const AUDCTL = 0x8;
pub const STIMER = 0x9;
pub const SKCTL = 0xF;

/// The reload delay after a borrow, in machine cycles: what makes the 1.79 MHz
/// periods N+4 (one channel) and N+7 (a joined pair) in the Altirra manual. On
/// the 64 / 15 kHz bases it is hidden inside the 28 / 114-cycle tick.
const DELAY_SINGLE: u3 = 3;
const DELAY_JOINED: u3 = 6;

/// The polynomial counters: Fibonacci shift registers shifting right, the new
/// bit XNORed in at the top, output = bit 0. XNOR (the NMOS chip's choice) makes
/// all-zero a live state, so init mode clears them to 0 and they run from there.
/// The 9-bit poly is the 17-bit register shortened: the feedback enters at bit 8
/// (and bit 16), so bits 0..8 cycle alone. Primitive trinomials, so the periods
/// are 15, 31, 511 and 131071 (pokey_test.zig counts them).
pub const Poly = struct {
    p4: u4 = 0, // x^4 + x + 1
    p5: u5 = 0, // x^5 + x^2 + 1
    p17: u17 = 0, // x^17 + x^5 + 1, or x^9 + x^4 + 1 in its low 9 bits

    pub fn shift(self: *Poly, nine: bool) void {
        const n4: u4 = ~(self.p4 ^ (self.p4 >> 1)) & 1;
        self.p4 = (self.p4 >> 1) | (n4 << 3);
        const n5: u5 = ~(self.p5 ^ (self.p5 >> 2)) & 1;
        self.p5 = (self.p5 >> 1) | (n5 << 4);
        const s = self.p17;
        const n: u17 = ~(s ^ (s >> if (nine) 4 else 5)) & 1;
        self.p17 = if (nine) ((s >> 1) & ~@as(u17, 0x10100)) | n << 8 | n << 16 else (s >> 1) | n << 16;
    }
};

const Chan = struct {
    cnt: u8 = 0,
    pend: u3 = 0, // cycles until the reload; the counter is frozen meanwhile
    out: u1 = 0, // the output flip-flop
};

pub const Pokey = struct {
    audf: [4]u8 = .{ 0, 0, 0, 0 },
    audc: [4]u8 = .{ 0, 0, 0, 0 },
    audctl: u8 = 0,
    skctl: u8 = 0, // power-up: init mode (bits 0-1 clear); the OS writes 3
    ch: [4]Chan = .{ .{}, .{}, .{}, .{} },
    hp: [2]u1 = .{ 0, 0 }, // the high-pass latches of channels 1 and 2
    poly: Poly = .{},
    div28: u8 = 0,
    div114: u8 = 0,

    pub fn write(self: *Pokey, addr: u4, v: u8) void {
        switch (addr) {
            0, 2, 4, 6 => self.audf[addr >> 1] = v,
            1, 3, 5, 7 => self.audc[addr >> 1] = v,
            AUDCTL => self.audctl = v,
            STIMER => self.stimer(),
            SKCTL => self.skctl = v,
            else => {},
        }
    }

    /// STIMER: every counter reloads from its AUDF now, and the output and
    /// high-pass flip-flops clear (a decision: see decisions.md, POKEY ADR).
    fn stimer(self: *Pokey) void {
        for (&self.ch, self.audf) |*c, f| c.* = .{ .cnt = f };
        self.hp = .{ 0, 0 };
    }

    /// One machine cycle.
    pub fn step(self: *Pokey) void {
        const init = self.skctl & 3 == 0;
        if (init) { // polys and bases held at 0
            self.poly = .{};
            self.div28 = 0;
            self.div114 = 0;
        }
        const t64 = !init and self.div28 == 27;
        const t15 = !init and self.div114 == 113;
        const base = if (self.audctl & 0x01 != 0) t15 else t64;
        const b12 = self.pair(0, self.audctl & 0x40 != 0 or base, base, self.audctl & 0x10 != 0);
        const b34 = self.pair(2, self.audctl & 0x20 != 0 or base, base, self.audctl & 0x08 != 0);
        const borrow = [4]bool{ b12[0], b12[1], b34[0], b34[1] };
        const old = [2]u1{ self.ch[0].out, self.ch[1].out };
        for (0..4) |i| {
            if (borrow[i]) self.ch[i].out = self.clockOut(i);
        }
        self.hp[0] = if (self.audctl & 0x04 == 0) 0 else if (borrow[2]) old[0] else self.hp[0];
        self.hp[1] = if (self.audctl & 0x02 == 0) 0 else if (borrow[3]) old[1] else self.hp[1];
        if (init) return;
        self.poly.shift(self.audctl & 0x80 != 0);
        self.div28 = if (t64) 0 else self.div28 + 1;
        self.div114 = if (t15) 0 else self.div114 + 1;
    }

    /// One channel's counter for this cycle; true on a borrow. `wrap` (the low
    /// half of a joined pair) rolls over to 0xFF instead of reloading.
    fn count(self: *Pokey, i: usize, tick: bool, wrap: bool) bool {
        const c = &self.ch[i];
        if (c.pend != 0) {
            c.pend -= 1;
            if (c.pend == 0) c.cnt = self.audf[i];
            return false;
        }
        if (!tick) return false;
        if (c.cnt != 0) {
            c.cnt -= 1;
            return false;
        }
        if (wrap) c.cnt = 0xFF else c.pend = DELAY_SINGLE;
        return true;
    }

    /// Channels lo and lo+1: independent, or joined (lo = low byte, clocking
    /// lo+1 with its borrows; both reload when lo+1 borrows).
    fn pair(self: *Pokey, lo: usize, tick_lo: bool, base: bool, join: bool) [2]bool {
        const bl = self.count(lo, tick_lo, join);
        const bh = self.count(lo + 1, if (join) bl else base, false);
        if (join and bh) {
            self.ch[lo].pend = DELAY_JOINED;
            self.ch[lo + 1].pend = DELAY_JOINED;
        }
        return .{ bl, bh };
    }

    /// The output flip-flop on a borrow, per AUDC bits 7-5: bit 7 clear gates
    /// the borrow with the 5-bit poly; bit 5 set toggles (pure tone); else the
    /// output takes the 4-bit poly (bit 6) or the 17/9-bit poly.
    fn clockOut(self: *const Pokey, i: usize) u1 {
        const c = self.audc[i];
        const o = self.ch[i].out;
        if (c & 0x80 == 0 and self.poly.p5 & 1 == 0) return o;
        if (c & 0x20 != 0) return ~o;
        if (c & 0x40 != 0) return @truncate(self.poly.p4);
        return @truncate(self.poly.p17);
    }

    /// Channel i's 4-bit level: its volume while its output is high (always,
    /// in volume-only mode), 0 otherwise. Channels 1 and 2 pass through their
    /// high-pass latch (an XOR; the latch is held at 0 while the filter is off).
    pub fn level(self: *const Pokey, i: usize) u4 {
        const c = self.audc[i];
        const vol: u4 = @truncate(c);
        if (c & 0x10 != 0) return vol;
        const o = if (i < 2) self.ch[i].out ^ self.hp[i] else self.ch[i].out;
        return if (o == 1) vol else 0;
    }

    /// The four levels summed, 0..60.
    pub fn mix(self: *const Pokey) u8 {
        var s: u8 = 0;
        for (0..4) |i| s += self.level(i);
        return s;
    }

    /// Fill `out` with the mix at `rate` Hz, each sample the mean over the
    /// machine cycles in its period (a box filter), scaled to 0..1. `frac`
    /// carries the fractional cycle between calls.
    pub fn render(self: *Pokey, out: []f32, rate: u32, frac: *u64) void {
        const den = CLOCK_DEN * rate;
        for (out) |*s| {
            frac.* += CLOCK_NUM;
            var sum: u64 = 0;
            var n: u64 = 0;
            while (frac.* >= den) : (frac.* -= den) {
                self.step();
                sum += self.mix();
                n += 1;
            }
            s.* = if (n == 0) 0 else @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(n * 60));
        }
    }
};
