/* See vstat.h. */
#include "vstat.h"

#include <stdio.h>

#include "bvstat.h"
#include "vboard.h"
#include "vseq.h"

static vstat_win g_win;
static vseq_stats g_s0; /* vseq when the frame began */
static uint32_t g_t0, g_comp0, g_dma0, g_flags;

static uint32_t sticky(void) {
    uint32_t st = zmv_status();
    return ((st & ZMV_BIT(UNDERRUN)) ? VSF_UNDERRUN : 0u) | ((st & ZMV_BIT(OVERFLOW)) ? VSF_OVERFLOW : 0u);
}

/* What one counter read costs: the probe's error on each timed span (VS_FLAGS bits 15:8). */
static uint32_t probe_cost(void) {
    uint32_t t0 = board_cycles();
    for (int i = 0; i < 16; i++) (void)board_cycles();
    uint32_t c = (board_cycles() - t0) / 17u;
    return c > 255u ? 255u : c;
}

void vstat_boot(void) {
    uint32_t now = sticky();
    g_flags = (now & VSF_UNDERRUN ? VSF_UNDERRUN_AT_BOOT : 0u) | probe_cost() << 8;
    bvstat_boot(&g_win, g_flags | now);
    vcal_run();
}

void vstat_begin(void) {
    g_s0 = vseq;
    g_comp0 = ZMV_REG(COMP_BUSY);
    g_dma0 = ZMV_REG(DMA_BUSY);
    g_t0 = board_cycles();
}

void vstat_end(long f, uint32_t cart, uint32_t seq) {
    uint32_t frame = board_cycles() - g_t0;
    uint32_t d[VS_NMEAN] = {
        frame, cart, seq, vseq.ready - g_s0.ready, vseq.drain - g_s0.drain, vseq.painted - g_s0.painted,
        vseq.hbl - g_s0.hbl, vseq.plan - g_s0.plan, vseq.passes - g_s0.passes, ZMV_REG(COMP_BUSY) - g_comp0,
        ZMV_REG(DMA_BUSY) - g_dma0, vseq.swap_wait - g_s0.swap_wait,
    };
    bvstat_frame(&g_win, d, g_flags | sticky());
#ifndef ZM_BOARD /* the sim's per-frame line; the board prints nothing */
    printf("ZM VS %ld", f);
    for (uint32_t i = 0; i < VS_NMEAN; i++) printf(" %lu", (unsigned long)d[i]);
    printf("\n");
#else
    (void)f;
#endif
}
