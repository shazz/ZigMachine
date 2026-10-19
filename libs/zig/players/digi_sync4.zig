// --------------------------------------------------------------------------
// The Swedish New Year Demo's "Sync" 4-voice digi mixer (ripped by Grazey),
// natively: Swedish_New_Year_Demo_Sync.sndh. A Timer A interrupt at 2457600
// / 4 / 80 = 7,680 Hz sums four voices' sample bytes and plays the sum
// through an 8-byte volume-table entry: about 128 interrupts a 60 Hz frame,
// ~181 % of BARD on Musashi. Only the handler is native (digi_irq.zig); init
// relocates it, so its absolute operands are only right once it has run.
//
// The handler is SELF-MODIFYING: each voice's sample pointer is the absolute
// operand of its own `move.b`/`add.b`, its end the immediate of a `cmpi.l`,
// its pitch stream the operand of a `tst.b`, its loop the immediate of a
// `move.l`; play patches them and the handler steps them through d16(a4)
// (a4 = `lea x(pc)`). So every operand is read from RAM at every interrupt,
// and the d16 targets are wherever the code says, not assumed to be its own.
// A voice plays while its flag byte is set (two flags are d16(a4), two are
// absolute). Offsets from voice v's sample instruction S (SAMPLE[v]):
//   S     move.b / add.b P.l,d7  the sample byte (voice 0 moves, 1-3 add)
//   S+6   cmpi.l #E,d16(a4) / blt: at or past E the flag is cleared (S+$10)
//         (voice 3: bmi, the sign of the difference)
//   S+$14 addq.l #1,d16(a4)      the pitch stream steps (voice 3: its pointer)
//   S+$18 tst.b Q.l: 0 holds the sample, plus steps it (addq.l #1, S+$2C),
//         minus rewinds the stream (move.l #L,d16(a4), S+$22). Not voice 3.
//   $CC   andi.w #$ff,d7 / lsl.w #3 / lea table(pc): movep.w the entry's low
//         word, swap, its high word, then its third word, onto $8800/$8802.
// With voice 0 off, d7's low byte is the interrupted code's (Bus.d7).
// The timer's end of interrupt is automatic (init clears VR bit 3).
//
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0xF6; // to the rte, inclusive
const A4_LEA: u32 = 0x04;
const TABLE_LEA: u32 = 0xD2;
const SAMPLE = [4]u32{ 0x0E, 0x46, 0x7C, 0xB4 };
pub const STEP = [4]u32{ 0x16, 0x4E, 0x84, 0xBC }; // each voice's end E, which play patches (S+8)
const FLAG = [4]u32{ 0x0A, 0x40, 0x78, 0xAE }; // tst.b d16(a4), abs.l, d16(a4), abs.l
const FLAG_ABS = [4]bool{ false, true, false, true };
// The operands play patches or init relocates: P, E, Q, L and the absolute flags
const HOLES = [_][2]u32{
    .{ 0x10, 0x14 }, .{ 0x16, 0x1A }, .{ 0x28, 0x2C }, .{ 0x32, 0x36 },
    .{ 0x40, 0x44 }, .{ 0x48, 0x4C }, .{ 0x4E, 0x52 }, .{ 0x60, 0x64 },
    .{ 0x6A, 0x6E }, .{ 0x7E, 0x82 }, .{ 0x84, 0x88 }, .{ 0x96, 0x9A },
    .{ 0xA0, 0xA4 }, .{ 0xAE, 0xB2 }, .{ 0xB6, 0xBA }, .{ 0xBC, 0xC0 },
};
const SIGNATURE: u64 = 0x7317CD4EF6D54FE1; // digi.maskedHash of [0, LEN), the holes zeroed
const FIRST: u32 = 0x48E71118; // movem.l d3/d7/a3-a4,-(a7): the quick reject
const PSG: u32 = 0xFF8800; // lea $8800.w: $FFFF8800 on the 68000's 24-bit bus

/// Where a voice's d16(a4) operands land, resolved at arming.
pub const Voice = struct { flag: u32 = 0, cmp: u32 = 0, clr: u32 = 0, step: u32 = 0, rewind: u32 = 0, advance: u32 = 0 };
pub const Driver = struct { addr: u32, v: [4]Voice = .{Voice{}} ** 4, table: u32 = 0 };

pub fn matchAt(image: []const u8, off: usize) bool {
    if (off + LEN > image.len or digi.be32(image, off) != FIRST) return false;
    return digi.maskedHash(image[off..][0..LEN], &HOLES) == SIGNATURE;
}

pub fn match(image: []const u8, base: u32) ?Driver {
    var off: usize = 0;
    while (off + LEN <= image.len) : (off += 2) {
        if (matchAt(image, off)) return .{ .addr = base + @as(u32, @intCast(off)) };
    }
    return null;
}

/// The relocated handler in RAM, checked again and its operands' addresses resolved.
pub fn arm(comptime Bus: type, d: *Driver) bool {
    var code: [LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = Bus.read8(d.addr + @as(u32, @intCast(i)));
    if (!matchAt(&code, 0)) return false;
    const a4 = digi.pcRel(d.addr + A4_LEA, digi.be16(&code, A4_LEA + 2));
    const at = struct {
        fn d16(c: []const u8, base: u32, off: u32) u32 {
            return base +% @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(digi.be16(c, off))))));
        }
    };
    for (&d.v, SAMPLE, 0..) |*v, s, i| {
        v.flag = if (FLAG_ABS[i]) digi.be32(&code, FLAG[i]) else at.d16(&code, a4, FLAG[i]);
        v.cmp = at.d16(&code, a4, s + 0x0C);
        v.clr = at.d16(&code, a4, s + 0x12);
        v.step = at.d16(&code, a4, s + 0x16);
        if (i < 3) {
            v.rewind = at.d16(&code, a4, s + 0x28);
            v.advance = at.d16(&code, a4, s + 0x2E);
        }
    }
    d.table = digi.pcRel(d.addr + TABLE_LEA, digi.be16(&code, TABLE_LEA + 2));
    return true;
}

/// Voice `i`'s byte, its end check and its pitch stream, as the code at S does them.
fn voice(comptime Bus: type, d: Driver, i: usize) u8 {
    const m = digi.Access(Bus);
    const s = d.addr + SAMPLE[i];
    const v = d.v[i];
    const b = m.rd8(m.rd32(s + 2));
    const end = digi.irq.step(Bus, d.addr + STEP[i], i);
    const x = m.rd32(v.cmp);
    // cmpi.l #E,ea is ea - E: blt is N xor V, a signed less-than; voice 3's bmi is N alone
    const before = if (i < 3) @as(i32, @bitCast(x)) < @as(i32, @bitCast(end)) else @as(i32, @bitCast(x -% end)) < 0;
    if (!before) m.wr8(v.clr, 0);
    m.wr32(v.step, m.rd32(v.step) +% 1);
    if (i == 3) return b;
    const q = m.rd8(m.rd32(s + 0x1A)); // the operand as the addq just left it
    if (q == 0) return b;
    if (q & 0x80 == 0) {
        m.wr32(v.advance, m.rd32(v.advance) +% 1);
    } else {
        m.wr32(v.rewind, m.rd32(s + 0x24));
    }
    return b;
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    var d7: u8 = @truncate(Bus.d7());
    for (0..4) |i| {
        if (m.rd8(d.v[i].flag) == 0) continue;
        const b = voice(Bus, d, i);
        d7 = if (i == 0) b else d7 +% b;
    }
    const e = d.table +% @as(u32, d7) * 8; // (a3,d7.w): at most $7F8, never negative
    const d3 = m.rd32(e);
    const third = m.rd16(e + 4);
    for ([_]u8{ @truncate(d3 >> 8), @truncate(d3), @truncate(d3 >> 24), @truncate(d3 >> 16), @truncate(third >> 8), @truncate(third) }, 0..) |x, k| {
        m.wr8(PSG + 2 * @as(u32, @intCast(k & 1)), x);
    }
}
