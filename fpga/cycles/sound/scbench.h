/* A plain C bench on the sound CPU (cycles/sound.mk snd-cbench): no players, no audio core.
 * The bench's own sources define cbench_run(); scbench.c boots it and ends the sim with its code.
 * Time a piece of work with cb_mark() / cb_frame(), which print what snd-bench prints for a
 * frame ("F <n> <cycles>" and "FW <n> <ibus waits> <dbus waits>") plus its share of BARD's frame. */
#ifndef ZM_SCBENCH_H
#define ZM_SCBENCH_H

#include <stdint.h>

#include "snd_mailbox.h"

#define CB_FRAME_BUDGET 1666667u /* BARD's cycles in a 60 Hz frame (100 MHz) */

typedef struct {
    uint32_t cycles, ibus, dbus;
} cb_mark_t;

static inline cb_mark_t cb_mark(void) {
    return (cb_mark_t){SND_REG(SND_CYCLES), SND_REG(SND_IBUS_WAIT), SND_REG(SND_DBUS_WAIT)};
}

/* Prints frame n's cost since t0 for `samples` output samples; returns its cycles. */
uint32_t cb_frame(int n, cb_mark_t t0, uint32_t samples);

/* The bench: 0 when it ran, else its failure code. */
int cbench_run(void);

#endif
