// --------------------------------------------------------------------------
// Quartet's SingSong 4-voice sample replay (Audio Visual Research, 1989),
// natively: the Dune Gen4 Demo's four "520 Soundtracker" tunes
// (dune_gen4_quartet.sndh, prototypes/dune_gen4_re/quartet/). A Timer A
// interrupt at 2457600 / 4 / 38 = 16,168 Hz adds four voices' sample bytes and
// plays the sum through an 8-byte-an-entry volume table: 270 interrupts a
// 60 Hz frame, ~374 % of BARD on Musashi (the survey). Only the handler is
// native; init, the 200 Hz sequencer (PLAY) and exit stay on Musashi.
//
// The state is in REGISTERS, not RAM: d0-d3 are the voices' positions (high
// word the sample offset, low word its fraction), a0-a3 their samples, a4 the
// PSG, d4/d5 the handler's scratch, all left live between interrupts; the
// sequencer starts a note by writing d_i and a_i itself. So the native handler
// reads them from Musashi's register file at each interrupt and writes back
// what the 68000 would have left (Bus.getReg / setReg): a PLAY in between
// sees exactly the 68000's registers.
//
// The Timer A vector is the SNDH glue's wrapper (LEN $18), which calls
// SingSong's handler as an interrupt, then saves d0 to memory, because the
// SNDH engine's PLAY arrives with d0 = 0:
//   $00  pea .post(pc); move.w sr,-(sp); move.l ta_orig(pc),-(sp); rts
//   $0C  .post: move.l a5,-(sp); lea saved_d0(pc),a5; move.l d0,(a5);
//        movea.l (sp)+,a5; rte
//   $18  saved_d0 (long)   $1C  ta_orig: SingSong's handler, set by init
// SingSong's handler (HLEN $5C), every address PC-relative to its TEXT:
//   $00  swap d0-d3; moveq #0,d4; move.b (a0,d0.w),d5: the offset word is a
//        SIGNED index; move.b (a1,d1.w),d4 / add.w d4,d5, x3; swap back
//   $28  lsl.w #3,d5; move.l table(pc,d5.w),d4; movep.l d4,(a4): registers
//        8 and 9 through $8800-$8806; move.w table+4(pc,d5.w),d4; movep.w:
//        register 10. The table follows the handler ($5C, 1024 entries).
//   $3A  moveq #0,d5; add.l step(pc),d_i / addx.w d5,d5, x4: the four
//        carries in d5 (voice 0 is bit 3); tst.w d5 / bne.w wrap; rte
// The wrap (XLEN $A2), relocated absolute addresses (the holes), per voice:
//   bclr #3-i,d5 / beq.w; tst.w flag_i.l / beq.w; lea silence.l,a_i;
//   move.l #$1000000,loop_i.l; sub.l loop_i.l,d_i   -- flag_i = loop_i + 2:
//   a loop long with a low word (no loop: $FFFFFFFF) sends the voice to
//   silence, 256 bytes of $80 the carry keeps it on; a loop length (its
//   high word, low word 0) is subtracted from the offset.
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0x18; // the wrapper, to its rte inclusive: saved_d0 and ta_orig follow
const SAVED: u32 = 0x18; // saved_d0
const ORIG: u32 = 0x1C; // ta_orig
const FIRST: u32 = 0x487A000A; // pea $0A(pc): the quick reject
const SIGNATURE: u64 = 0x44B64DDB58ED00E7; // digi.maskedHash of [0, LEN), no holes
pub const STEP = [0]u32{}; // the steps are the sequencer's words, not immediates in the code

pub const HLEN: u32 = 0x5C; // SingSong's handler, to its rte inclusive
const HFIRST: u32 = 0x48404841; // swap d0; swap d1
const HSIGNATURE: u64 = 0x9F3FDC55B9476083;
const TABLE_MOVE: u32 = 0x2A; // move.l d8(pc,d5.w),d4: its extension word at $2C
const STEP_ADD = [4]u32{ 0x3C, 0x42, 0x48, 0x4E }; // add.l d16(pc),d_i
const WRAP_BNE: u32 = 0x56; // bne.w wrap

const XLEN: u32 = 0xA2; // the wrap, to its rte inclusive; XVOICE a voice's block of it
const XVOICE: u32 = 0x28;
const XFLAG: u32 = 0x0A; // tst.w flag.l: the abs.l (then beq.w)
const XSILENCE: u32 = 0x14; // lea silence.l,a_i
const XLOOP: u32 = 0x1E; // move.l #$1000000,loop.l: the abs.l
const XSUB: u32 = 0x24; // sub.l loop.l,d_i
const XHOLES = [_][2]u32{
    .{ 0x0A, 0x0E }, .{ 0x14, 0x18 }, .{ 0x1E, 0x22 }, .{ 0x24, 0x28 },
    .{ 0x32, 0x36 }, .{ 0x3C, 0x40 }, .{ 0x46, 0x4A }, .{ 0x4C, 0x50 },
    .{ 0x5A, 0x5E }, .{ 0x64, 0x68 }, .{ 0x6E, 0x72 }, .{ 0x74, 0x78 },
    .{ 0x82, 0x86 }, .{ 0x8C, 0x90 }, .{ 0x96, 0x9A }, .{ 0x9C, 0xA0 },
};
const XSIGNATURE: u64 = 0xAB48BA8A24E62872; // digi.maskedHash of [0, XLEN), the abs.l zeroed

const NO_HOLES = [_][2]u32{};
const D0: u4 = 0; // Musashi's register numbers: d0-d7 then a0-a7
const D4: u4 = 4;
const D5: u4 = 5;
const A0: u4 = 8;
const A4: u4 = 12;
const BUS: u32 = 0xFFFFFF; // the 68000's 24-bit bus: `(a0,d0.w)` wraps there

/// The wrapper's address (the Timer A vector), then SingSong's handler and
/// its addresses, read from RAM once init has relocated it (digi_irq.zig `arm`).
pub const Driver = struct {
    addr: u32,
    handler: u32 = 0,
    table: u32 = 0,
    step: [4]u32 = undefined, // each voice's step long
    loop: [4]u32 = undefined, // each voice's loop long; its low word is the flag
    silence: u32 = 0,
};

pub fn matchAt(image: []const u8, off: usize) bool {
    if (off + LEN > image.len or digi.be32(image, off) != FIRST) return false;
    return digi.maskedHash(image[off..][0..LEN], &NO_HOLES) == SIGNATURE;
}

fn handlerAt(image: []const u8, off: usize) bool {
    if (off + HLEN > image.len or digi.be32(image, off) != HFIRST) return false;
    return digi.maskedHash(image[off..][0..HLEN], &NO_HOLES) == HSIGNATURE;
}

fn find(image: []const u8, comptime at: fn ([]const u8, usize) bool) ?usize {
    var off: usize = 0;
    while (off + LEN <= image.len) : (off += 2) {
        if (at(image, off)) return off;
    }
    return null;
}

/// The glue's wrapper, with SingSong's handler somewhere in the image: the wrapper
/// alone is generic glue, the handler alone is any SingSong program.
pub fn match(image: []const u8, base: u32) ?Driver {
    const w = find(image, matchAt) orelse return null;
    if (find(image, handlerAt) == null) return null;
    return .{ .addr = base + @as(u32, @intCast(w)) };
}

fn read(comptime Bus: type, at: u32, buf: []u8) void {
    for (buf, 0..) |*b, i| b.* = Bus.read8(at + @as(u32, @intCast(i)));
}

/// The wrapper, then the handler ta_orig points at and its wrap routine, checked
/// in RAM and their addresses read. False: not the replay (Musashi plays it).
pub fn arm(comptime Bus: type, d: *Driver) bool {
    var w: [LEN]u8 = undefined;
    read(Bus, d.addr, &w);
    if (!matchAt(&w, 0)) return false;
    d.handler = digi.Access(Bus).rd32(d.addr + ORIG);
    var h: [HLEN]u8 = undefined;
    read(Bus, d.handler, &h);
    if (!handlerAt(&h, 0)) return false;
    // d8(pc,Xn): the base is the extension word's address plus its signed low byte
    const ext = digi.be16(&h, TABLE_MOVE + 2);
    d.table = d.handler + TABLE_MOVE + 2 +% @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(ext)))))));
    for (&d.step, STEP_ADD) |*s, at| s.* = digi.pcRel(d.handler + at, digi.be16(&h, at + 2));
    return armWrap(Bus, d, digi.pcRel(d.handler + WRAP_BNE, digi.be16(&h, WRAP_BNE + 2)));
}

fn armWrap(comptime Bus: type, d: *Driver, at: u32) bool {
    var x: [XLEN]u8 = undefined;
    read(Bus, at, &x);
    if (digi.maskedHash(&x, &XHOLES) != XSIGNATURE) return false;
    d.silence = digi.be32(&x, XSILENCE);
    for (&d.loop, 0..) |*l, i| {
        const b = XVOICE * @as(u32, @intCast(i));
        l.* = digi.be32(&x, b + XLOOP);
        if (digi.be32(&x, b + XSUB) != l.* or digi.be32(&x, b + XFLAG) != l.* + 2) return false;
        if (digi.be32(&x, b + XSILENCE) != d.silence) return false;
    }
    return true;
}

/// `(a_i,d_i.w)` after the swap: the offset word, sign-extended (or not: mutant 7).
fn sample(a: u32, pos: u32) u32 {
    const off: u16 = @truncate(pos >> 16);
    const idx: u32 = if (digi.irq.unsigned_index) off else @bitCast(@as(i32, @as(i16, @bitCast(off))));
    return (a +% idx) & BUS;
}

/// The volume table's entry: movep.l then movep.w onto the PSG, and d4 as both leave it.
fn play(comptime Bus: type, d: Driver, sum: u16) void {
    const m = digi.Access(Bus);
    const idx: u32 = @bitCast(@as(i32, @as(i16, @bitCast(sum *% 8)))); // lsl.w #3: a signed word index
    const e = d.table +% idx;
    const hi = m.rd32(e);
    const a4 = Bus.getReg(A4) & BUS;
    for (0..4) |i| m.wr8(a4 +% 2 * @as(u32, @intCast(i)), @truncate(hi >> @intCast(24 - 8 * i)));
    const lo = m.rd16(e + 4);
    m.wr8(a4, @truncate(lo >> 8));
    m.wr8(a4 +% 2, @truncate(lo));
    Bus.setReg(D4, (hi & 0xFFFF0000) | lo);
}

/// A voice whose offset carried: back by its loop, or to silence when its loop long has a low word.
fn wrap(comptime Bus: type, d: Driver, r: *[4]u32, carries: u32) void {
    const m = digi.Access(Bus);
    for (r, 0..) |*pos, i| {
        if (carries & (@as(u32, 8) >> @intCast(i)) == 0) continue;
        if (m.rd16(d.loop[i] + 2) != 0) {
            Bus.setReg(A0 + @as(u4, @intCast(i)), d.silence);
            m.wr32(d.loop[i], 0x01000000);
        }
        pos.* -%= m.rd32(d.loop[i]);
    }
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    var r: [4]u32 = undefined;
    var sum: u16 = @as(u16, @truncate(Bus.getReg(D5))) & 0xFF00; // move.b keeps d5's upper byte
    for (&r, 0..) |*pos, i| {
        pos.* = Bus.getReg(D0 + @as(u4, @intCast(i)));
        sum +%= m.rd8(sample(Bus.getReg(A0 + @as(u4, @intCast(i))), pos.*));
    }
    play(Bus, d, sum);
    var carries: u32 = 0;
    for (&r, d.step) |*pos, step| {
        const s = @addWithOverflow(pos.*, m.rd32(step));
        pos.* = s[0];
        carries = (carries << 1) | s[1];
    }
    if (carries != 0) wrap(Bus, d, &r, carries);
    for (r, 0..) |pos, i| Bus.setReg(D0 + @as(u4, @intCast(i)), pos);
    Bus.setReg(D5, 0); // every carry bit cleared again
    m.wr32(d.addr + SAVED, r[0]); // the wrapper's .post
}
