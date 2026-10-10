/* hwBlit on the board (bblit.c): the counters bmain.c reports as "ZM BLIT". */
#ifndef ZM_BBLIT_H
#define ZM_BBLIT_H

#include <stdint.h>

#define BBLIT_TRACE 192

typedef struct {
    uint32_t calls;  /* hwBlit() calls */
    uint32_t hw;     /* of which zm_blit ran (the rest: the machine's, before VBASE is set, or ZM_BLIT=sw) */
    uint32_t cycles; /* CPU cycles inside hwBlit(), mod 2^32 */
    /* Per command (index = BLIT_CMD_*: 1 BLIT, 2 FILL, 3 LINE, 4 TRIANGLE; 0 anything else),
     * since the last bblit_frame_reset(): the sim's per-frame "ZM BF" line (bmain.c). */
    uint32_t op_calls[5];
    uint32_t op_cycles[5]; /* CPU cycles inside hwBlit() */
    uint32_t op_units[5];  /* the ops' CYCLES (pixels written; FILL: W*H) */
    /* The frame's calls in order (the first BBLIT_TRACE): what ran, the CPU cycles since the
     * previous hwBlit returned (or the frame began: the cart's own code), and its own cycles. */
    uint32_t n_trace, t_last;
    struct { uint8_t cmd; uint32_t gap, cycles, units; } trace[BBLIT_TRACE];
} bblit_stats;

void bblit_frame_reset(void);

extern bblit_stats bblit;

#endif
