/* hwBlit on the board (bblit.c): the counters bmain.c reports as "ZM BLIT". */
#ifndef ZM_BBLIT_H
#define ZM_BBLIT_H

#include <stdint.h>

typedef struct {
    uint32_t calls;  /* hwBlit() calls */
    uint32_t hw;     /* of which zm_blit ran (the rest: the machine's, before VBASE is set, or ZM_BLIT=sw) */
    uint32_t cycles; /* CPU cycles inside hwBlit(), mod 2^32 */
} bblit_stats;

extern bblit_stats bblit;

#endif
