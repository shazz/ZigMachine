// The PAL Amiga's beam counter (Agnus VPOSR $DFF004 / VHPOSR $DFF006), derived
// from the 68000 cycles run since the vertical blank. Pure: natively tested
// (amiga_beam_test.zig); paula.zig answers the reads with it.
//
// WHY. Replay routines wait for the beam: Rings of Medusa's player spins on
// `move.b 6(a6),d6 / cmp.b 6(a6),d6 / beq` (VHPOSR's horizontal byte changing)
// between switching DMA off and writing the new pointers, so Paula has time to
// notice. A counter that reads 0 for ever hangs it; one that moves with the
// CPU's own cycles ends every such wait after as long as it takes on an Amiga.
//
// The numbers: the PAL 68000 runs at 7.09 MHz, two CPU cycles a colour clock;
// a line is 227 colour clocks (the real PAL line alternates 227/228: the
// half clock is dropped), a frame 313 lines (non-interlaced, long frame bit
// clear). PLAY is called from the vertical blank, which starts at line 0.

pub const CYCLES_PER_CLOCK: u32 = 2;
pub const CLOCKS_PER_LINE: u32 = 227;
pub const LINES: u32 = 313;
pub const CYCLES_PER_LINE: u32 = CYCLES_PER_CLOCK * CLOCKS_PER_LINE;
pub const CYCLES_PER_FRAME: u32 = CYCLES_PER_LINE * LINES;

pub const Beam = struct { line: u16, clock: u8 };

/// Where the beam is `cycles` 68000 cycles after the vertical blank.
pub fn at(cycles: u32) Beam {
    const c = cycles % CYCLES_PER_FRAME;
    return .{
        .line = @intCast(c / CYCLES_PER_LINE),
        .clock = @intCast((c % CYCLES_PER_LINE) / CYCLES_PER_CLOCK),
    };
}

/// VHPOSR: V7-V0 in the high byte, H8-H1 (colour clocks) in the low byte.
pub fn vhposr(cycles: u32) u16 {
    const b = at(cycles);
    return ((b.line & 0xFF) << 8) | b.clock;
}

/// VPOSR: V8 in bit 0. Bit 15 (long frame) clear, Agnus ID bits 8-14 = 0
/// (an OCS PAL Agnus, as an A500 has).
pub fn vposr(cycles: u32) u16 {
    return at(cycles).line >> 8;
}
