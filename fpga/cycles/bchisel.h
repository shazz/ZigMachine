/* CHISEL under hwBlit (bchisel.c): GO, the wait, and the lazy wait a cart opts into with
 * BLIT_ASYNC (machine/sdk/memmap.zig). Force-included (-include bchisel.h) into the generated
 * env.c / sys_env.c, where HOST_CHISEL_SYNC is the wait tools/host_gen.py puts in front of every
 * machine and ROM entry and behind every HBL handler: "when unsure, wait".
 *
 * The lazy wait: with BLIT_ASYNC set, hwBlit() returns once CHISEL has STARTED, not finished. The
 * cart promises not to touch the op's source or destination pixels until it syncs (a NOP hwBlit,
 * libs/zig/chisel_async.zig); everything else the firmware owns waits here first: the next
 * hwBlit, any machine or ROM call, the end of cart.frame() and of each HBL handler. */
#ifndef ZM_BCHISEL_H
#define ZM_BCHISEL_H

#include <stdint.h>

extern uint8_t bchisel_pending; /* a lazy op may still be running */

/* The op in the block at r (COMMAND != 0 runs it; NOP only waits for a lazy one). */
void bchisel_run(volatile uint8_t* r);
/* Wait for the lazy op, then what the synchronous hwBlit would have done after it. */
void bchisel_sync(void);

#define BCHISEL_SYNC()                      \
    do {                                    \
        if (bchisel_pending) bchisel_sync(); \
    } while (0)
#define HOST_CHISEL_SYNC() BCHISEL_SYNC()

#endif
