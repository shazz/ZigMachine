// --------------------------------------------------------------------------
// Mad Max's 3-voice digi mixer (1988, converted by Grazey), natively: the
// B.I.G. Demo's "digital" tunes (Ace 2, Labello, Phantom of the Asteroid,
// Sanxion, Starpaws) and big/Labello. A Timer A interrupt at 2457600 / 4 / 64
// = 9600 Hz adds three voices' sample bytes and plays the sum through a
// volume table, 160 times a 60 Hz frame. The handler is native, and so is the
// 50 Hz play when it is Mad Max's sequencer (all six are: digi_big_play.zig);
// init and exit stay on Musashi (digi_irq.zig).
//
// Offsets from the handler (the init copies it, then relocates it):
//   $0A  addi.l #step1,$382.w   the step is patched by play (self-modifying)
//   $12  movea.l $380.w,a0      voice 1: pointer $380, its fraction at $384
//   $16  add.b (a0),d0 / bpl    a byte with bit 7 set ends the sample:
//   $1A  tst.w F1 / beq         F1 set: on $42 to the loop (and F1 cleared),
//   $34  suba.l L1,a0           else back by the loop's length L1
//   $40  voice 2 ($386 / $388): added with carry; a carry ends the sample,
//        whose loop byte is added again, then 1
//   $78  voice 3 ($38C / $38E): a carry clips to $FF unless the byte is
//        negative (the end): then as voice 2, but a carry clips to $FF
//   $C6  asl.w #3 / lea table(pc,d0.w): movep.l + movep.w onto $8800-$8806
//   $E2  in the file `bclr #5,$FFFA11` (a software end of interrupt) then
//        rte; init writes an rte over the bclr. The native handler is only
//        armed once it has (the MFP is left alone, as on the 68000).
//
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0xE2; // to the patched tail
const RTE: u32 = 0xE2; // where init writes the rte
const TABLE: u32 = 0xEC; // lea $22(pc,d0.w) at $C8
pub const STEP = [3]u32{ 0x0C, 0x42, 0x7A }; // each voice's addi.l immediate
const SITES = [3]u32{ 0x10, 0x46, 0x7E }; // each voice's addi.l address word
const FLAG = [3]u32{ 0x1C, 0x52, 0x98 }; // tst.w F (abs.l)
const CLR = [3]u32{ 0x2C, 0x62, 0xA8 }; // clr.w F: the same F
const LOOP = [3]u32{ 0x36, 0x6C, 0xB2 }; // suba.l L (abs.l)
const HOLES = [_][2]u32{
    .{ 0x0C, 0x10 }, .{ 0x1C, 0x20 }, .{ 0x2C, 0x30 }, .{ 0x36, 0x3A },
    .{ 0x42, 0x46 }, .{ 0x52, 0x56 }, .{ 0x62, 0x66 }, .{ 0x6C, 0x70 },
    .{ 0x7A, 0x7E }, .{ 0x98, 0x9C }, .{ 0xA8, 0xAC }, .{ 0xB2, 0xB6 },
};
const SIGNATURE: u64 = 0x3AA922E97BAF9EE1; // digi.maskedHash of [0, LEN), steps and abs.l zeroed
const FIRST: u32 = 0x2F082F00; // move.l a0,-(a7); move.l d0,-(a7): the quick reject

pub const Voice = struct { ptr: u32, flag: u32, loop: u32 };
/// The handler's address, then its voices, read from RAM once the tune's init
/// has relocated it (digi_irq.zig `arm`). `play`: the tune's PLAY, when it is
/// Mad Max's sequencer (digi_big_map.zig), which then runs natively too; 0 if not.
pub const Driver = struct { addr: u32, v: [3]Voice = undefined, play: u32 = 0 };

/// Is the handler at image offset `off`?
pub fn matchAt(image: []const u8, off: usize) bool {
    if (off + LEN > image.len or digi.be32(image, off) != FIRST) return false;
    return digi.maskedHash(image[off..][0..LEN], &HOLES) == SIGNATURE;
}

pub fn match(image: []const u8, base: u32) ?Driver {
    var off: usize = 0;
    while (off + LEN <= image.len) : (off += 2) {
        if (!matchAt(image, off)) continue;
        const play = @import("digi_big_map.zig").playOf(image);
        return .{ .addr = base + @as(u32, @intCast(off)), .play = if (play) |p| base + p else 0 };
    }
    return null;
}

/// The relocated handler in RAM, checked again and its addresses read. False:
/// it is not the handler any more (the caller plays it on Musashi).
pub fn arm(comptime Bus: type, d: *Driver) bool {
    var code: [LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = Bus.read8(d.addr + @as(u32, @intCast(i)));
    if (!matchAt(&code, 0)) return false;
    if (digi.Access(Bus).rd16(d.addr + RTE) != 0x4E73) return false; // not yet the rte
    for (&d.v, 0..) |*v, i| {
        if (digi.be32(&code, FLAG[i]) != digi.be32(&code, CLR[i])) return false;
        v.* = .{ .ptr = digi.be16(&code, SITES[i]) -% 2, .flag = digi.be32(&code, FLAG[i]), .loop = digi.be32(&code, LOOP[i]) };
    }
    return true;
}

/// The sample's end: on $42 to its loop once (F set), else back by its length.
fn wrap(comptime Bus: type, v: Voice, a: u32) u32 {
    const m = digi.Access(Bus);
    if (m.rd16(v.flag) != 0) {
        m.wr16(v.flag, 0);
        return a +% 0x42;
    }
    return a -% m.rd32(v.loop);
}

/// `addi.l #step,ptr+2` (the step read from the code, as play patched it), then the pointer.
fn step(comptime Bus: type, d: Driver, i: usize) u32 {
    const m = digi.Access(Bus);
    const v = d.v[i];
    m.wr32(v.ptr + 2, m.rd32(v.ptr + 2) +% digi.irq.step(Bus, d.addr + STEP[i], i));
    return m.rd32(v.ptr);
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    var a = step(Bus, d, 0);
    var s: u8 = m.rd8(a);
    if (s & 0x80 != 0) {
        a = wrap(Bus, d.v[0], a);
        m.wr32(d.v[0].ptr, a);
        s = m.rd8(a);
    }
    a = step(Bus, d, 1);
    const c = @addWithOverflow(s, m.rd8(a));
    s = c[0];
    if (c[1] != 0) {
        a = wrap(Bus, d.v[1], a);
        m.wr32(d.v[1].ptr, a);
        s = s +% m.rd8(a) +% 1;
    }
    s = voice3(Bus, d, s);
    const e = d.addr + TABLE + @as(u32, s) * 8;
    const hi = m.rd32(e);
    const lo = m.rd16(e + 4);
    const PSG: u32 = 0xFF8800; // movea.w #$8800,a0: $FFFF8800, on the 68000's 24-bit bus
    for (0..4) |i| m.wr8(PSG + 2 * @as(u32, @intCast(i)), @truncate(hi >> @intCast(24 - 8 * i)));
    m.wr8(PSG, @truncate(lo >> 8));
    m.wr8(PSG + 2, @truncate(lo));
}

fn voice3(comptime Bus: type, d: Driver, sum: u8) u8 {
    const m = digi.Access(Bus);
    var a = step(Bus, d, 2);
    var c = @addWithOverflow(sum, m.rd8(a));
    if (c[1] == 0) return c[0];
    if (m.rd8(a) & 0x80 == 0) return 0xFF; // tst.b (a0): a loud byte clips
    a = wrap(Bus, d.v[2], a);
    m.wr32(d.v[2].ptr, a);
    c = @addWithOverflow(c[0], m.rd8(a));
    if (c[1] != 0) return 0xFF;
    c = @addWithOverflow(c[0], @as(u8, 1));
    return if (c[1] != 0) 0xFF else c[0];
}
