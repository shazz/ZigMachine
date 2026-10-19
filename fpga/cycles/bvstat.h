/* The video probe's block of the debug mailbox (glass/src/map_cart.zig "the video probe"): a
 * frame's phases summed over a window and published as per-frame means, for the glass's ZMSTAT
 * line (glass/src/vstat.zig) and fpga/tools/board_fps.py. cycles/vstat.c measures; this header
 * only sums and publishes, so tests/test_vstat.py runs it on the host against an array.
 *
 * A window closes after VSTAT_FRAMES frames, or sooner once its frames pass VSTAT_MAX_CYCLES
 * (a 2 fps cart still reports every second). The sums are 64-bit: a mean never overflows. */
#ifndef ZM_BVSTAT_H
#define ZM_BVSTAT_H

#include <stdint.h>

#include "glass_cart.h" /* gen/: map_cart.zig's VSTAT_*, VS_*, VSF_* */

#ifndef ZM_VSTAT_BLOCK /* tests/test_vstat.py points it at an array */
#define ZM_VSTAT_BLOCK ((volatile uint32_t*)(0x42000000u - MB_BYTES) + VSTAT_AT)
#endif

#define VS_NMEAN (VSTAT_WORDS - VS_FRAME) /* the means, VS_FRAME .. VS_SWAP */

typedef struct {
    uint64_t sum[VS_NMEAN];
    uint32_t n, flags;
} vstat_win;

/* At boot, after mb_init zeroed the page: an empty block (n = 0), with what is known already. */
static inline void bvstat_boot(vstat_win* w, uint32_t flags) {
    volatile uint32_t* b = ZM_VSTAT_BLOCK;
    for (uint32_t i = 0; i < VS_NMEAN; i++) w->sum[i] = 0;
    w->n = 0, w->flags = flags;
    for (uint32_t i = VS_SEQ; i < VSTAT_WORDS; i++) b[i] = 0;
    b[VS_FLAGS] = flags;
    b[VS_MAGIC] = VSTAT_MAGIC; /* last: a reader that sees it sees the rest */
}

static inline void bvstat_publish(vstat_win* w) {
    volatile uint32_t* b = ZM_VSTAT_BLOCK;
    b[VS_SEQ] = b[VS_SEQ] | 1u;
    b[VS_N] = w->n;
    b[VS_FLAGS] = w->flags;
#ifdef BVSTAT_BREAK_MEAN /* tests/test_vstat.py's mutant (ZM_RTL_BREAK=1): the sums, not the means */
    for (uint32_t i = 0; i < VS_NMEAN; i++) b[VS_FRAME + i] = (uint32_t)w->sum[i];
#else
    for (uint32_t i = 0; i < VS_NMEAN; i++) b[VS_FRAME + i] = (uint32_t)(w->sum[i] / w->n);
#endif
    b[VS_SEQ] = b[VS_SEQ] + 1u;
    for (uint32_t i = 0; i < VS_NMEAN; i++) w->sum[i] = 0;
    w->n = 0;
}

/* One frame's figures, d[i] for word VS_FRAME + i; `flags` the sticky bits now. */
static inline void bvstat_frame(vstat_win* w, const uint32_t d[VS_NMEAN], uint32_t flags) {
    for (uint32_t i = 0; i < VS_NMEAN; i++) w->sum[i] += d[i];
    w->n++, w->flags = flags;
    if (w->n >= VSTAT_FRAMES || w->sum[0] >= VSTAT_MAX_CYCLES) bvstat_publish(w);
}

#endif
