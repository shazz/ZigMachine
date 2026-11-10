/* env.hwAstro on the board (bastro.c, SPIKE: docs/ARM_FPU_COPROC.md): ASTROLABE through the
 * mailbox to the ARM, the machine's own code when nobody serves it. */
#ifndef ZM_BASTRO_H
#define ZM_BASTRO_H

#include <stdint.h>

/* At boot, after host_boot_machine: the cart's memory, and whether the bitstream has the
 * mailbox (STATUS.ASTRO). */
void bastro_boot(uint8_t* mem, uint64_t size);

typedef struct {
    uint32_t calls;    /* hwAstro() calls */
    uint32_t served;   /* ...the ARM answered */
    uint32_t untaken;  /* ...posted, not taken in time: the machine's code ran */
    uint32_t timeouts; /* ...taken, not done in time: ST_TIMEOUT */
    uint32_t cycles;   /* ZIGGY cycles inside hwAstro(), mod 2^32 */
    uint32_t arm_ns;   /* the last served request's time on the ARM */
} bastro_stats;
extern bastro_stats bastro;

#endif
