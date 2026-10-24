// The Amiga's Paula, as an Amiga replay routine sees it from the 68000's bus,
// mapped onto this machine's four sample channels (machinePaula*).
//
// WHY THIS EXISTS. An Amiga module such as Jochen Hippel's .hip is not data
// for a tracker: it is the game's own 68000 replay code, which pokes Paula's
// registers at $DFF0A0.. fifty times a second. hip_player.zig runs that code
// on the SNDH player's Musashi; this is the chip it talks to. The same split as
// the ST: the machine emulates the CPU, the machine's own channels make the sound.
//
// THE ONE THING THAT DECIDES THE SOUND: AUDxLC/AUDxLEN ARE DOUBLE-BUFFERED.
// Paula copies them into its live pointer and counter only when DMA is switched
// on, and again each time the live counter runs out. That is how every Amiga
// replay plays "attack, then loop": it starts the voice on the whole sample and,
// a frame later, writes the loop's pointer and length, which Paula picks up at
// the end of the first pass. Hippel's synth sounds lean on it harder still: they
// write a new 16-byte waveform pointer EVERY frame with DMA left running, and
// Paula moves on to it only when the current cycle ends. Applied at once, that
// would cut the waveform 50 times a second (a buzz); latched at the wrap it is
// the real sound. So a voice with a pending pointer is rendered only up to its
// wrap (samplesToLatch), and re-triggered there (advance), as ste_dma.zig does
// at the DMA chip's frame end. A voice with nothing pending loops on the
// machine's channel by itself, sub-sample exact.
//
// WHAT IS NOT HERE, named rather than silently missing:
//   * audio interrupts (INTENA/INTREQ bits 7-10): kept as shadows, never raised.
//     A replay that ENABLES them (bit 15 set with any of bits 7-10) is counted
//     in `irq_wanted`: its handler would never run.
//   * AUDxDAT (CPU-driven, non-DMA output) and ADKCON's modulation: a write to
//     any register not modelled here is refused, so the bus counts it in the
//     SNDH player's unhandled-address list (audioUnhandled*), never silent.
//   * the LED low-pass filter (CIA-A PRA bit 1): the bit is kept, not applied.
//   * a re-latch lands on an output sample: the cycle's sub-sample phase (under
//     one 44.1 kHz sample) is dropped when the pointer moves.
const audio = @import("audio_hw");
const mod = @import("mod.zig");

pub const BASE: u32 = 0xDFF000;
pub const SIZE: u32 = 0x200;
pub const CIAA_PRA: u32 = 0xBFE001;

const DMACONR: u32 = 0x002;
const INTENAR: u32 = 0x01C;
const INTREQR: u32 = 0x01E;
const DMACON: u32 = 0x096;
const INTENA: u32 = 0x09A;
const INTREQ: u32 = 0x09C;
const AUD0: u32 = 0x0A0; // + 16 per voice: LCH, LCL, LEN, PER, VOL, DAT
const SET: u16 = 0x8000; // DMACON/INTENA/INTREQ: 1 sets the bits written, 0 clears them
const AUD_IRQS: u16 = 0x0780; // INTENA bits 7-10: AUD0..AUD3

/// PAL Paula: a sample every `period` ticks of 3,546,895 Hz.
const PAULA_CLOCK: u64 = 3_546_895;
const OUT_RATE: u64 = 44_100;
const FRAC: u6 = 16; // the machine's channels step in 16.16

const Voice = struct {
    // the registers, as last written: the latch's input
    lc: u32 = 0,
    len: u16 = 0, // in words; 0 means 65,536
    step: u32 = 0,
    // what the channel is playing now
    on: bool = false,
    span: u64 = 0, // the live region's length in bytes, 16.16
    pos: u64 = 0, // where the channel is inside it, 16.16 (shadows the machine's)
    pending: bool = false, // LC/LEN written since the last latch
};

/// Decode $DFF000.. and $BFE001 only while an Amiga module runs: an ST tune
/// that writes there is counted as unhandled, as it always was.
pub var enabled: bool = false;
/// Test only: 1 = DMACON's switch-on edge is ignored, so no voice ever starts;
/// 2 = LC/LEN written to a playing voice are taken at once, not at its wrap.
pub var mutant: u32 = 0;

var voices: [4]Voice = [_]Voice{.{}} ** 4;
var dmacon: u16 = 0;
var intena: u16 = 0;
var intreq: u16 = 0;
var ciaa_pra: u8 = 0;
/// Diagnosis: voices started by a DMA switch-on edge, LC/LEN latched at a wrap,
/// voices refused (a pointer outside the 68000's RAM), interrupts asked for.
pub var starts: [4]u32 = [_]u32{0} ** 4;
pub var latches: u32 = 0;
pub var bad_ptr: u32 = 0;
pub var irq_wanted: u32 = 0;

pub fn claims(addr: u32) bool {
    return enabled and ((addr >= BASE and addr < BASE + SIZE) or addr == CIAA_PRA);
}

/// Power-up: every voice off, the counters zero. `on` decodes the window.
pub fn reset(on: bool) void {
    for (0..4) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    voices = [_]Voice{.{}} ** 4;
    dmacon = 0;
    intena = 0;
    intreq = 0;
    ciaa_pra = 0;
    starts = [_]u32{0} ** 4;
    latches = 0;
    bad_ptr = 0;
    irq_wanted = 0;
    enabled = on;
}

pub fn read16(addr: u32) u16 {
    if (addr == CIAA_PRA) return ciaa_pra;
    return switch (addr - BASE) {
        DMACONR => dmacon,
        INTENAR => intena,
        INTREQR => intreq,
        else => 0,
    };
}

pub fn read8(addr: u32) u8 {
    if (addr == CIAA_PRA) return ciaa_pra;
    const w = read16(addr & ~@as(u32, 1));
    return if (addr & 1 == 0) @truncate(w >> 8) else @truncate(w);
}

/// A byte written to a custom-chip register lands in both halves of the word, as
/// on the Amiga's 16-bit chip bus. False: a register nothing here models.
pub fn write8(addr: u32, value: u8) bool {
    if (addr == CIAA_PRA) {
        ciaa_pra = value;
        return true;
    }
    return write16(addr & ~@as(u32, 1), (@as(u16, value) << 8) | value);
}

pub fn write16(addr: u32, value: u16) bool {
    if (addr == CIAA_PRA) return write8(addr, @truncate(value));
    const reg = addr - BASE;
    switch (reg) {
        DMACON => setDma(value),
        INTENA => {
            if (value & SET != 0 and value & AUD_IRQS != 0) irq_wanted +%= 1;
            intena = setClear(intena, value);
        },
        INTREQ => intreq = setClear(intreq, value),
        AUD0...AUD0 + 0x3F => return voiceWrite(@intCast((reg - AUD0) >> 4), (reg - AUD0) & 0xF, value),
        else => return false,
    }
    return true;
}

fn setClear(old: u16, value: u16) u16 {
    return if (value & SET != 0) old | (value & 0x7FFF) else old & ~value;
}

fn voiceWrite(ch: u2, r: u32, value: u16) bool {
    const v = &voices[ch];
    switch (r) {
        0x0 => v.lc = (v.lc & 0xFFFF) | (@as(u32, value & 0x1F) << 16), // LCH: 21 address bits
        0x2 => v.lc = (v.lc & 0x1F_0000) | (value & 0xFFFE), // LCL: word aligned
        0x4 => v.len = value,
        0x6 => {
            v.step = stepOf(value);
            audio.machinePaulaSetStep(ch, v.step);
            return true;
        },
        0x8 => {
            audio.machinePaulaSetVolume(ch, mod.chipVolume(@intCast(@min(value & 0x7F, 64))));
            return true;
        },
        else => return false, // AUDxDAT: CPU-driven output, not modelled
    }
    v.pending = true; // LC or LEN: picked up at the next switch-on or wrap
    if (mutant == 2 and v.on and latch(ch)) v.pos = 0; // wrong: taken at once, mid-cycle
    return true;
}

/// Bytes advanced per 44.1 kHz output sample, 16.16. Period 0 holds the voice.
fn stepOf(period: u16) u32 {
    if (period == 0) return 0;
    return @intCast((PAULA_CLOCK << FRAC) / (@as(u64, period) * OUT_RATE));
}

fn setDma(value: u16) void {
    const was = dmacon;
    dmacon = setClear(dmacon, value);
    for (0..4) |i| {
        const ch: u2 = @intCast(i);
        const bit = @as(u16, 1) << ch;
        if (was & bit == 0 and dmacon & bit != 0) {
            if (mutant != 1) start(ch);
        } else if (was & bit != 0 and dmacon & bit == 0) {
            voices[ch].on = false;
            audio.machinePaulaSetActive(ch, 0);
        }
    }
}

/// DMA switched on: LC/LEN latched, the voice plays from the start of them.
fn start(ch: u2) void {
    if (!latch(ch)) return;
    voices[ch].pos = 0;
    starts[ch] +%= 1;
}

/// Copy LC/LEN into the live region and (re)start the machine's channel on it,
/// looping the whole region until the next latch. False (voice off) when the
/// region is not inside the 68000's RAM.
fn latch(ch: u2) bool {
    const v = &voices[ch];
    const bytes: u32 = if (v.len == 0) 0x20000 else @as(u32, v.len) * 2;
    v.pending = false;
    if (@as(u64, v.lc) + bytes > audio.SONG_CAP) {
        bad_ptr +%= 1;
        v.on = false;
        audio.machinePaulaSetActive(ch, 0);
        return false;
    }
    audio.machinePaulaTrigger(ch, audio.songAddr(v.lc), bytes, 0, bytes, mod.pan(ch));
    audio.machinePaulaSetStep(ch, v.step);
    v.span = @as(u64, bytes) << FRAC;
    v.on = true;
    return true;
}

/// Output samples until the first voice with a pending LC/LEN wraps (at least
/// 1), or `max` if none will within it.
pub fn samplesToLatch(max: u32) u32 {
    var n = max;
    for (&voices) |*v| {
        if (!v.on or !v.pending or v.step == 0) continue;
        const left = v.span - v.pos; // > 0: pos is kept inside the region
        n = @min(n, @as(u32, @intCast(@min((left + v.step - 1) / v.step, max))));
    }
    return @max(n, 1);
}

/// `block` samples were mixed: move every voice on, re-latching each one with a
/// pending LC/LEN that reached its wrap.
pub fn advance(block: u32) void {
    for (&voices, 0..) |*v, i| {
        if (!v.on) continue;
        v.pos += @as(u64, block) * v.step;
        if (v.pos < v.span) continue;
        if (!v.pending) {
            v.pos %= v.span;
            continue;
        }
        const over = v.pos - v.span;
        const ch: u2 = @intCast(i);
        if (!latch(ch)) continue;
        latches +%= 1;
        // The machine's channel takes a whole-sample position: keep the shadow on it.
        const whole = (over % v.span) >> FRAC;
        audio.machinePaulaSetPos(ch, @intCast(whole));
        v.pos = whole << FRAC;
    }
}
