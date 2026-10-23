/* CHISEL under hwBlit (bchisel.c): GO, the wait, and the lazy wait a cart opts into with
 * BLIT_ASYNC (machine/sdk/memmap.zig). Force-included (-include bchisel.h) into the generated
 * env.c / sys_env.c, where HOST_CHISEL_SYNC is the wait tools/host_gen.py puts in front of every
 * machine and ROM entry and behind every HBL handler: "when unsure, wait".
 *
 * The lazy wait: with BLIT_ASYNC set, hwBlit() returns once CHISEL has STARTED, not finished. The
 * cart promises not to touch the op's source or destination pixels until it syncs (a NOP hwBlit,
 * libs/zig/chisel_async.zig); everything else the firmware owns waits here first: the next
 * hwBlit, any machine or ROM call, the end of cart.frame() and of each HBL handler.
 *
 * A QUEUE (COMMAND 5, memmap BLIT_CMD_QUEUE) is always lazy: CHISEL runs the cart's descriptor
 * list from its own copy of the ring while the cart goes on, and the same waits apply. */
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

/* The env entries' wait. A plain call here, even never taken, turned every machine and ROM
 * entry from a two-instruction tail jump into a function with a stack frame: two stores and two
 * loads of the same stack line per call, and a load behind a posted store waits for it, so a cart
 * making many such calls lost up to 0.68 Mc a frame (rno_natrium 60 -> 55 fps, union_l16 36 -> 31
 * on the board, 2026-10-20). So on the board the rare path goes through bchisel_sync_saved
 * (bchisel.c), reached by `jal t0` and saving every other caller-saved integer register itself:
 * the entry only loses t0, keeps its tail jump and gets no frame. bchisel_sync is integer code,
 * so the FP caller-saved registers are not touched. */
#ifdef __riscv /* the generated env is built without ZM_BLIT_HW: bchisel.c has the stub either way */
#define HOST_CHISEL_SYNC()                                                             \
    do {                                                                               \
        if (__builtin_expect(bchisel_pending, 0))                                      \
            __asm__ volatile("jal t0, bchisel_sync_saved" ::: "t0", "memory");          \
    } while (0)
#else
#define HOST_CHISEL_SYNC() BCHISEL_SYNC()
#endif

#endif
