// --------------------------------------------------------------------------
// The 3-voice volume-table byte replay: one Timer A interrupt plays one 8-bit
// sample byte through a 256-entry table onto the YM's three volume registers.
// It is in eleven SNDHs of the collection (Beat Dis, Robocop, Sidewinder, Joe
// Blade 2, ...: prototypes/beatdis_re/README.md), each with its own sequencer.
//
//   movem.l d0-d2/a0-a1,-(a7)
//   lea     cur(pc),a0          ; the sample pointer (long)
//   movea.l (a0),a1
//   move.b  (a1)+,d0
//   move.l  a1,(a0)
//   andi.w  #$ff,d0
//   addi.b  #$80,d0             ; signed sample -> table index
//   lsl.w   #3,d0               ; 8 bytes an entry: 08 a 09 b 0A c 00 00
//   lea     table(pc),a0
//   adda.w  d0,a0
//   lea     $8800.w,a1
//   ... d0/d1/d2 = $0800vv00 / $0900vv00 / $0A00vv00 from bytes 1, 3, 5
//   move.l  d0,(a1) / d1,(a1) / d2,(a1)
//   movem.l (a7)+,d0-d2/a0-a1
//   rte
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0x52;
const CUR_LEA: u32 = 0x04; // the two `lea d16(pc)`: their displacements are masked
const TABLE_LEA: u32 = 0x18;
const HOLES = [_][2]u32{ .{ CUR_LEA + 2, CUR_LEA + 4 }, .{ TABLE_LEA + 2, TABLE_LEA + 4 } };
const SIGNATURE: u64 = 0x60F3B04405109D86; // digi.maskedHash of Beat Dis's handler
const FIRST: u32 = 0x48E7E0C0; // movem.l d0-d2/a0-a1,-(a7): the quick reject

pub const Handler = struct {
    addr: u32, // the handler's 68000 address (what the tune installs at $134)
    cur: u32, // its sample pointer
    table: u32, // its volume table
};

/// Is the handler at image offset `off`? Its addresses, if so.
pub fn match(image: []const u8, base: u32, off: usize) ?Handler {
    if (off + LEN > image.len or digi.be32(image, off) != FIRST) return null;
    if (digi.maskedHash(image[off..][0..LEN], &HOLES) != SIGNATURE) return null;
    const at = base + @as(u32, @intCast(off));
    return .{
        .addr = at,
        .cur = digi.pcRel(at + CUR_LEA, digi.be16(image, off + CUR_LEA + 2)),
        .table = digi.pcRel(at + TABLE_LEA, digi.be16(image, off + TABLE_LEA + 2)),
    };
}

/// The first offset of the handler in `image`, on an even address.
pub fn find(image: []const u8) ?u32 {
    var off: usize = 0;
    while (off + LEN <= image.len) : (off += 2) {
        if (match(image, 0, off) != null) return @intCast(off);
    }
    return null;
}

const PSG: u32 = 0xFF8800;

/// One interrupt, every access in the 68000's order. The pushes and pops of the
/// movem are left out: nothing reads that stack.
pub fn irq(comptime Bus: type, h: Handler) void {
    const m = digi.Access(Bus);
    const pos = m.rd32(h.cur);
    const b = Bus.read8(pos);
    m.wr32(h.cur, pos +% 1);
    const entry = h.table +% @as(u32, b +% 0x80) * 8;
    const a = Bus.read8(entry + 1);
    const v = Bus.read8(entry + 3);
    const c = Bus.read8(entry + 5);
    m.wr32(PSG, 0x0800_0000 | @as(u32, a) << 8);
    m.wr32(PSG, 0x0900_0000 | @as(u32, v) << 8);
    m.wr32(PSG, 0x0A00_0000 | @as(u32, c) << 8);
}

/// Mode 3 (sndh_native.zig): the interrupt moves the pointer on and writes
/// nothing, so the PCM channel and a switch back to the YM agree on the sample.
pub fn skip(comptime Bus: type, h: Handler) void {
    const m = digi.Access(Bus);
    m.wr32(h.cur, m.rd32(h.cur) +% 1);
}
