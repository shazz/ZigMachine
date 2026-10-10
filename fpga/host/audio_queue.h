/* The board's write queue (cycles/baudio.c, zm_audio_soc's 2048 stamped writes):
 * what it drops and how far ahead of the sound it runs. One header so the native
 * host can model the same queue (host/audio_soft.c ZM_AUDIO_QUEUE) and a test can
 * hold the board to it over a whole tune (tests/test_sndh_native.py).
 *
 * Dropped: a YM volume write (regs 8-10) of the value last QUEUED for that register.
 * A volume register has no side effect, so the sound is the same; the period and
 * envelope registers are never dropped (a write to reg 13 restarts the envelope).
 * A digi tune writes the three volumes at 15.75 kHz and 38 % of those change
 * nothing (Beat Dis). The chip reset forgets what was queued.
 *
 * The lead: four 60 Hz frames, but three for a native digi replay, whose ~788
 * writes a frame would otherwise not fit the queue at four. */
#ifndef ZM_AUDIO_QUEUE_H
#define ZM_AUDIO_QUEUE_H

#include <stdint.h>

#include "audio_regs.h"

#define ZMA_DEPTH 2048u    /* zm_audio_soc QAW = 11 */
#define ZMA_FRAME 735u     /* samples in a 60 Hz frame */
#define ZMA_NATIVE_DIGI 1u /* libs/zig/players/digi.zig Status.beat_dis */

typedef struct {
    uint32_t vol[3]; /* the last value queued to regs 8, 9, 10; ~0 = unknown */
} zma_dedup;

static inline void zma_dedup_forget(zma_dedup* d) { d->vol[0] = d->vol[1] = d->vol[2] = ~0u; }

/* 1: queue the write; 0: it changes nothing, drop it. */
static inline int zma_dedup_keep(zma_dedup* d, uint32_t addr, uint32_t data) {
    if (addr == ZMA_CTRL) {
        zma_dedup_forget(d);
        return 1;
    }
    uint32_t i = (addr - (ZMA_YM + 4u * 8u)) / 4u;
    if (addr < ZMA_YM + 4u * 8u || i > 2u) return 1;
    if (d->vol[i] == data) return 0;
    d->vol[i] = data;
    return 1;
}

/* The lead in samples for the player audioSndhNative() reports. */
static inline uint32_t zma_lead(uint32_t native) { return (native == ZMA_NATIVE_DIGI ? 3u : 4u) * ZMA_FRAME; }

#endif
