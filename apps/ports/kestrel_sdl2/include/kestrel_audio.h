/* The ports' audio feed, paced by real time (decisions.md 2026-10-17, "hostMicros may pace a cart's
 * audio feed"; extended to the C ports 2026-11-02).
 *
 * A port's SDL audio callback is also its replayer's clock (pt2's Paula ticks, klystrack's cyd, the
 * ChipNomad player), and the machine's stream ring plays in real time. Fed a fixed rate/60 samples a
 * frame, a cart below 60 fps hands over too little: the song slows down and the ring replays stale
 * bytes. So each frame:
 *
 *   uint32_t us = kestrel_frame_us(elapsed_ms, cap_ms); // once a frame: the time since the last frame
 *   kestrel_audio_pump(us, rate, lead_ms, mix, ctx);
 *
 * kestrel_frame_us() is env.hostMicros when the host has a clock (the browser, the board) and the
 * frame's dt otherwise (0 from every harness: frames stay deterministic). On the board dt is a
 * constant 16.6 ms whatever the frame rate, which is why dt alone is not enough. A frame longer than
 * cap_ms (a load, a stall, or a synth the CPU cannot run in real time) is cut there: the song skips that
 * time rather than burst it, and a port whose mixer costs more than real time keeps its frame rate
 * (each port says why its cap is what it is).
 * The ports' SDL clocks advance by the same `us`, so their visuals stay in step with the audio. */
#ifndef KESTREL_AUDIO_H
#define KESTREL_AUDIO_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Microseconds since the previous call (the first call: the frame's dt), capped at cap_ms. */
uint32_t kestrel_frame_us(float elapsed_ms, uint32_t cap_ms);

/* Fill `frames` S16 stereo frames (interleaved L R). */
typedef void (*kestrel_mix_fn)(void *ctx, int16_t *stereo, int frames);

/* Run `mix` for what `us` owes at `rate` (a fractional sample is carried to the next frame), in blocks,
 * and feed it to the stream as signed 8-bit mono ((L+R)/2). The first call starts the stream at `rate`
 * and feeds `lead_ms` of silence ahead of the speaker, which must exceed the port's slowest frame or
 * the speaker catches the feed up. */
void kestrel_audio_pump(uint32_t us, uint32_t rate, uint32_t lead_ms, kestrel_mix_fn mix, void *ctx);

/* Quiet (on = 1): the pump keeps running `mix` (a replayer's clock) but feeds nothing, and a stream
 * already started is stopped; a port whose sound plays elsewhere (pt2 on the hardware Paula channels,
 * HW 1.14.0) says so. Off again: the next pump restarts the stream with its lead. */
void kestrel_audio_quiet(int on);

#ifdef __cplusplus
}
#endif
#endif
