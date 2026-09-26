// The STE's DMA sound chip, for tunes whose SNDH header carries FLAG `a`.
//
// WHY THIS EXISTS. The Digital Department's five tunes are `FLAG~ay`: YM *and*
// STE DMA samples. The SNDH player's bus emulated $FF8800..$FF8803 and ignored
// everything else, so every digidrum was written into the void and what played
// was the YM part alone — thin and noisy, which is what Matt heard.
//
// The whole chip is four things: a start address, an end address, a rate, and a
// go bit. A frame of 8-bit SIGNED PCM is read out of ST RAM at one of four
// fixed rates and either stops at the end or loops. That maps onto this
// machine's Paula-style sample channels almost exactly, which is what this does
// rather than emulating a second mixer.
//
// STEREO WITHOUT A STRIDE. The STE interleaves L,R,L,R in one buffer, and a
// Paula channel has no stride — it reads consecutive bytes. The trick is that
// its step is fractional: give the left channel the buffer from byte 0 and the
// right the SAME buffer from byte 1, and step both at TWO bytes per output
// frame. Each then reads every other byte, which is exactly de-interleaving,
// with no copy and no scratch buffer.
//
// WHAT IS NOT HERE, named rather than silently missing:
//   * the frame-end interrupt (MFP GPIP 7). Nothing we play polls it; tunes
//     poll the go bit, which is cleared below when a one-shot runs out.
//   * the Microwire volume and tone SETTINGS ($FF8922/$FF8924): the master
//     volume and tone a tune sends are not applied. The TRANSFER is emulated,
//     because tunes wait on it: writing the data register shifts 16 bits out,
//     and while it does the mask register reads back rotated one bit per shift,
//     returning to the written mask after 16. maxYMiser's STE path writes $7FF
//     to the mask, the command to the data, then spins until the mask reads
//     something else and again until it reads $7FF: a mask that only ever read
//     back $7FF hung those tunes in their init (crystallized.sndh, D-Bug).
//   * the real chip latches start/end at the END of a frame. Here they are
//     latched when the go bit is set, which is a frame early at worst.
const std = @import("std");
const audio = @import("audio_hw");

pub const BASE: u32 = 0xFF8900;
pub const SIZE: u32 = 0x40; // $FF8900..$FF893F: control, pointers, mode, Microwire

const CTRL: u32 = 0x01; // bit 0 = play, bit 1 = loop
const START_HI: u32 = 0x03; // +0x03/0x05/0x07
const COUNT_HI: u32 = 0x09; // +0x09/0x0B/0x0D, read-only: where the chip is now
const END_HI: u32 = 0x0F; // +0x0F/0x11/0x13
const MODE: u32 = 0x21; // bits 0-1 = rate, bit 7 = MONO
const MW_DATA: u32 = 0x22; // Microwire data, $FF8922 (word)
const MW_MASK: u32 = 0x24; // Microwire mask, $FF8924 (word)

/// The four rates the chip can be clocked at, in Hz.
const RATES = [4]f32{ 6258, 12517, 25033, 50066 };
/// Which sample channels the DMA owns. The SNDH player uses no others.
const CH_L: u32 = 0;
const CH_R: u32 = 1;

var regs: [SIZE]u8 = [_]u8{0} ** SIZE;
/// Microwire shifts still to go in the current transfer (16 per data write).
/// One shift per read of the mask's low byte: a word read sees one position,
/// and a spinning tune watches the mask walk round and come home.
var mw_left: u8 = 0;
var playing: bool = false;
var stereo: bool = false;
/// Bytes consumed since the frame started, 16.16 — the counter registers are
/// read off this, and it is what decides when a one-shot has run out.
var pos: u64 = 0;
var step: u32 = 0; // bytes per output frame, 16.16
var span: u32 = 0; // frame length in bytes

/// Diagnosis for the harness: how many register writes the chip has seen and
/// how many frames it has started. A tune that probes for an STE and decides it
/// is on a plain STF writes NOTHING here, which looks exactly like a chip that
/// does not work — these two numbers tell those apart.
pub var writes: u32 = 0;
pub var starts: u32 = 0;

pub fn reset() void {
    regs = [_]u8{0} ** SIZE;
    mw_left = 0;
    playing = false;
    pos = 0;
    audio.machinePaulaSetActive(CH_L, 0);
    audio.machinePaulaSetActive(CH_R, 0);
}

pub fn read(addr: u32) u8 {
    const r = addr - BASE;
    if (r >= SIZE) return 0;
    // The counter registers are live: a tune that watches the chip walk through
    // its buffer must see it move, not see back what it wrote.
    if (r >= COUNT_HI and r <= COUNT_HI + 4) {
        const here = base24(START_HI) +% @as(u32, @intCast(pos >> 16));
        return switch (r) {
            COUNT_HI => @truncate(here >> 16),
            COUNT_HI + 2 => @truncate(here >> 8),
            COUNT_HI + 4 => @truncate(here),
            else => 0,
        };
    }
    if ((r == MW_MASK or r == MW_MASK + 1) and mw_left != 0) return microwireMask(r);
    return regs[r];
}

/// The mask during a transfer: the written mask rotated left by the shifts done.
fn microwireMask(r: u32) u8 {
    const mask: u16 = (@as(u16, regs[MW_MASK]) << 8) | regs[MW_MASK + 1];
    const done: u4 = @intCast(16 - @as(u32, mw_left));
    const now = std.math.rotl(u16, mask, done);
    if (r == MW_MASK) return @truncate(now >> 8);
    mw_left -= 1; // the low byte ends a word read: the next one sees the next shift
    return @truncate(now);
}

pub fn write(addr: u32, value: u8) void {
    const r = addr - BASE;
    if (r >= SIZE) return;
    writes +%= 1;
    const was = regs[CTRL] & 1;
    regs[r] = value;
    if (r == MW_DATA or r == MW_DATA + 1) mw_left = 16; // a transfer starts
    if (r != CTRL) return;
    if (value & 1 != 0) {
        if (was == 0) begin();
    } else if (playing) {
        playing = false;
        audio.machinePaulaSetActive(CH_L, 0);
        audio.machinePaulaSetActive(CH_R, 0);
    }
}

/// Consume `frames` output frames of the current DMA frame. A one-shot that
/// runs out clears its own go bit, which is how a tune knows it finished.
pub fn advance(frames: u32) void {
    if (!playing) return;
    pos += @as(u64, step) * frames;
    const total = @as(u64, span) << 16;
    if (pos < total) return;
    if (regs[CTRL] & 2 != 0) {
        pos -= total * (pos / total); // the channels loop themselves
        return;
    }
    playing = false;
    regs[CTRL] &= ~@as(u8, 1);
    audio.machinePaulaSetActive(CH_L, 0);
    audio.machinePaulaSetActive(CH_R, 0);
}

/// A 24-bit pointer out of its three registers, which sit two apart.
fn base24(first: u32) u32 {
    return (@as(u32, regs[first]) << 16) | (@as(u32, regs[first + 2]) << 8) | regs[first + 4];
}

fn begin() void {
    const from = base24(START_HI);
    const to = base24(END_HI);
    if (to <= from) return; // an empty or inverted frame plays nothing
    stereo = regs[MODE] & 0x80 == 0;
    // Both channels read every OTHER byte when stereo, so both step twice as
    // fast; the byte counter uses the same number because that IS the rate the
    // chip empties the buffer at.
    const bytes_per_frame = RATES[regs[MODE] & 3] / audio.SAMPLE_RATE * (if (stereo) @as(f32, 2) else 1);
    step = @intFromFloat(bytes_per_frame * audio.FRAC_ONE);
    // An odd length would leave the right channel a byte short of the left and
    // they would drift apart by one byte per loop.
    span = if (stereo) (to - from) & ~@as(u32, 1) else to - from;
    pos = 0;
    playing = true;
    starts +%= 1;
    const loop: u32 = if (regs[CTRL] & 2 != 0) span else 0;
    audio.machinePaulaTrigger(CH_L, audio.songAddr(from), span, 0, loop, if (stereo) -1.0 else 0.0);
    audio.machinePaulaSetStep(CH_L, step);
    audio.machinePaulaSetVolume(CH_L, 1.0);
    if (!stereo) {
        audio.machinePaulaSetActive(CH_R, 0);
        return;
    }
    audio.machinePaulaTrigger(CH_R, audio.songAddr(from + 1), span, 0, loop, 1.0);
    audio.machinePaulaSetStep(CH_R, step);
    audio.machinePaulaSetVolume(CH_R, 1.0);
}
