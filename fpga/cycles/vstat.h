/* The video probe (perf/fresco-probe): where a frame's time goes on the board, measured by the
 * firmware itself and published for the glass (cycles/bvstat.h, glass/src/map_cart.zig "the video
 * probe"). vseq.c built with ZM_VSTAT times its waits, handlers and decisions into `vseq`
 * (vseq_wait.h); this takes each frame's differences, with FRESCO's own COMP_BUSY and DMA_BUSY.
 *
 * In bmain.c: vstat_boot after mb_init (which zeroes the page), vstat_begin / vstat_end around
 * each frame. The sim (not ZM_BOARD) also prints each frame:
 *   "ZM VS f frame cart seq ready drain painted hbl plan passes comp dma swap"   (bvstat.h order) */
#ifndef ZM_VSTAT_H
#define ZM_VSTAT_H

#include <stdint.h>

/* Also runs vcal_run (vcal.c): the row costs, before the cart's first frame. */
void vstat_boot(void);
void vcal_run(void);
void vstat_begin(void);
/* cart: cart.frame()'s cycles; seq: the sequencer's (clear, planner, passes, PRESENT). */
void vstat_end(long f, uint32_t cart, uint32_t seq);

#endif
