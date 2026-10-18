// --------------------------------------------------------------------------
// Mode 3 of a native digi replay (sndh_native.zig): the samples on a PCM
// channel at the timer's rate, instead of through the YM's volume table. Any
// byte-a-tick driver that says where its pointer and samples are (digi.Pcm):
// Beat Dis and Wow Scroller.
//
// The tune's bytes cannot be played as they are: they are UNSIGNED and
// INVERTED (digi_handler.zig linear), and a PCM channel plays signed bytes.
// Played raw, every sample folded at its midpoint: noise in rhythm, on the board
// and in the browser alike (2026-10-11). So the load also writes the samples,
// converted, into a SHADOW above the image, reserved from the 68000's heap, and
// the channel plays the shadow. The tune's own bytes are never touched.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const digi = @import("digi.zig");

const CH: u32 = 0; // ste_dma.zig's left channel: a digi tune does not use the DMA chip
/// The handler plays past `end` until the next 50 Hz play: at most timer / 50 bytes
/// (Beat Dis 316, Wow Scroller 152).
const OVERSHOOT: u32 = 320;

/// The samples' 68000 range [lo, hi) and its converted copy at `to`.
pub const Shadow = struct { lo: u32, hi: u32, to: u32 };

/// The samples to the end of the image and the handler's overshoot past it,
/// each byte made linear, written above it (same phase mod 4) if they fit by `top`.
pub fn build(p: digi.Pcm, end: u32, top: u32) ?Shadow {
    const hi = end + OVERSHOOT;
    const to = ((hi + 0xF) & ~@as(u32, 0xF)) + (p.lo & 0xF);
    if (p.lo >= end or to + (hi - p.lo) > top) return null;
    const ram: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    for (ram[to..][0 .. hi - p.lo], ram[p.lo..hi]) |*o, b| o.* = digi.handler.linear(b);
    return .{ .lo = p.lo, .hi = hi, .to = to };
}

/// Play from the sample pointer to the segment's end and on as far as the
/// handler would, at the timer's rate, from the shadow (`raw`: the tune's own
/// bytes, the 2026-10-11 bug, for mutant 2); play() starts the next segment.
pub fn start(comptime Bus: type, p: digi.Pcm, shadow: ?Shadow, raw: bool) void {
    const sh = shadow orelse return stop();
    const m = digi.Access(Bus);
    const pos = m.rd32(p.cur) & 0xFF_FFFF;
    const end = m.rd32(p.end) & 0xFF_FFFF;
    if (pos < sh.lo or pos >= sh.hi) return stop();
    const len = @min(@max(end + 1, pos) - pos + OVERSHOOT, sh.hi - pos);
    const at = if (raw) pos else sh.to + (pos - sh.lo);
    audio.machinePaulaTrigger(CH, audio.songAddr(at), len, 0, 0, 0.0);
    audio.machinePaulaSetStep(CH, @intFromFloat(p.hz / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(CH, VOLUME);
}

pub fn stop() void {
    audio.machinePaulaSetActive(CH, 0);
}

/// The PCM channel's level against the YM's: Beat Dis's first 20 s measure an AC
/// RMS of 3900 in mode 2 and 7734 in mode 3 at 1.0, so 0.504, here as 129/256
/// (the audio core's volume grid, host/audio_regs.h zma_vol). Wow Scroller's
/// volume table is Beat Dis's, so the same level.
const VOLUME: f32 = 129.0 / 256.0;
