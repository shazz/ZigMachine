/* The sound CPU's side of snd-cbench (scbench.h): answer the cart CPU's boot (cycles/bsound.c)
 * at once, so a long bench setup never looks like a dead sound CPU, then run the bench and end. */
#include <stdio.h>

#include "scbench.h"
#include "sound.h"
#include "trap.h"

#define S2C(w) SND_REG(SND_S2C + (w))
#define C2S(w) SND_REG(SND_C2S + (w))

uint32_t cb_frame(int n, cb_mark_t t0, uint32_t samples) {
    cb_mark_t t1 = cb_mark();
    uint32_t c = t1.cycles - t0.cycles;
    uint32_t per10 = samples ? (uint32_t)((uint64_t)c * 10u / samples) : 0;
    uint32_t pct10 = (uint32_t)((uint64_t)c * 1000u / CB_FRAME_BUDGET);
    printf("F %d %lu\nFW %d %lu %lu\nFS %d %lu samples %lu.%lu cyc/sample %lu.%lu %%\n", n, (unsigned long)c, n,
           (unsigned long)(t1.ibus - t0.ibus), (unsigned long)(t1.dbus - t0.dbus), n, (unsigned long)samples,
           (unsigned long)(per10 / 10), (unsigned long)(per10 % 10), (unsigned long)(pct10 / 10),
           (unsigned long)(pct10 % 10));
    return c;
}

int main(void) {
    trap_install();
    S2C(S_ACK) = C2S(C_SEQ); /* the boot's nonce: this side is up */
    S2C(S_READY) = S_READY_VALUE;
    sound_finish(cbench_run());
}
