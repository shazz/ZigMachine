/* See vplan.h. */
#include "vplan.h"

#include <stdio.h>
#include <string.h>

#include "bmailbox.h" /* the two pictures */
#include "vboard.h"
#include "vdirty.h"
#include "vseq.h"
#include "zm_memmap.h"

#define ROW_BYTES (ZM_RASTER_WIDTH * 4u)

vplan_stats vplan;
static uint8_t g_skip[VD_LINES];
static int g_planned, g_composited;
static uint32_t g_plan_cycles; /* the comparison: what the plan costs the CPU */

#ifdef ZM_VSEQ_CHECK
static volatile uint32_t* picture(int pic) { return (volatile uint32_t*)(uintptr_t)(pic ? ZM_FB1_ADDR : ZM_FB0_ADDR); }

/* The rows the plan would have skipped, as the picture held them before this frame. */
static uint32_t g_before[VD_LINES][ZM_RASTER_WIDTH];
static int g_pic;

static void check_begin(int pic) {
    zmv_flush_dcache(); /* the compositor wrote the picture behind the D$ */
    for (uint32_t y = 0; y < VD_LINES; y++)
        if (g_skip[y]) memcpy(g_before[y], (const void*)(picture(pic) + y * ZM_RASTER_WIDTH), ROW_BYTES);
    g_pic = pic;
}

static void check_end(long f) {
    uint32_t rows = 0, bad = 0;
    vseq_idle();
    zmv_flush_dcache();
    for (uint32_t y = 0; y < VD_LINES; y++) {
        if (!g_skip[y]) continue;
        rows++;
        if (memcmp(g_before[y], (const void*)(picture(g_pic) + y * ZM_RASTER_WIDTH), ROW_BYTES)) {
            if (bad++ < 4) printf("ZM VCHK %ld row %lu differs\n", f, (unsigned long)y);
        }
    }
    vplan.checked += rows, vplan.mismatched += bad;
    printf("ZM VCHK %ld %lu %lu\n", f, (unsigned long)rows, (unsigned long)bad);
}
#endif

/* The rest of this frame composites every line; its skipped ones are not trusted (vdirty.h). */
void vplan_mask_moved(void) {
    vd_mask_moved();
    vseq_skip = NULL;
}

int vplan_frame(struct w2c_env* e, unsigned enabled, int full) {
    vd_frame fr = {e->memory.data, (uint32_t)e->memory.size, enabled, vseq_rec.fill, vseq_rec.bg, vseq_rec.beam};
    zmv_flush_dcache(); /* plane rows the blitter wrote behind the D$ */
    uint32_t t0 = board_cycles();
    int handler = vd_plan(&fr);
    g_plan_cycles = board_cycles() - t0;
    vseq_wait_swap(); /* the back picture is now the one this frame builds */
    int pic = (zmv_status() & ZMV_BIT(FRONT)) ? 0 : 1;
    g_composited = vd_target(pic, g_skip);
    g_planned = 1;
    vplan.lines += VD_LINES;
#ifdef ZM_VSEQ_CHECK
    (void)full;
    check_begin(pic);
#else
    if (!full) {
        vseq_skip = g_skip;
        vplan.skipped += VD_LINES - (uint32_t)g_composited;
    }
#endif
    return handler;
}

void vplan_end(long f) {
    if (!g_planned) return;
    g_planned = 0;
    vseq_skip = NULL;
#ifndef ZM_BOARD /* the lines the plan composites (all of them in a check), and its cost */
    printf("ZM VD %ld %d %lu\n", f, g_composited, (unsigned long)g_plan_cycles);
#endif
#ifdef ZM_VSEQ_CHECK
    check_end(f);
#endif
    (void)f;
}

void vplan_overdrawn(uint32_t back_addr, uint32_t y0, uint32_t n) { vd_overdrawn(back_addr == ZM_FB0_ADDR ? 0 : 1, y0, n); }

void vplan_report(void) {
    printf("ZM VPLAN %lu %lu %lu %lu %lu\n", (unsigned long)vplan.lines, (unsigned long)vplan.skipped,
           (unsigned long)vd.frames, (unsigned long)vd.unknown, (unsigned long)vd.mask_moved);
#ifdef ZM_VSEQ_CHECK
    printf("ZM VCHK total %lu %lu\n", (unsigned long)vplan.checked, (unsigned long)vplan.mismatched);
#endif
}
