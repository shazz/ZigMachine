/* See vplan.h. */
#include "vplan.h"

#include <stdio.h>
#include <string.h>

#include "bmailbox.h" /* the two pictures */
#include "vadapt.h"
#include "vboard.h"
#include "vdirty.h"
#include "vseq.h"
#include "zm_memmap.h"

#define ROW_BYTES (ZM_RASTER_WIDTH * 4u)

vplan_stats vplan;
static uint8_t g_skip[VD_LINES];
static int g_planned, g_full, g_pic, g_composited;
static uint32_t g_decided, g_plan_cycles; /* g_plan_cycles: the frame's comparisons before the swap */
static uint32_t g_t0, g_wait0; /* when the planes' phase began, and the swap wait so far (vadapt.h) */
static int g_timed;

#ifdef ZM_VSEQ_CHECK
/* The rows the plan would have skipped, as the picture held them before this frame. */
static uint32_t g_before[VD_LINES][ZM_RASTER_WIDTH];
static uint8_t g_would[VD_LINES];

static volatile uint32_t* row_of(uint32_t y) {
    return (volatile uint32_t*)(uintptr_t)(g_pic ? ZM_FB1_ADDR : ZM_FB0_ADDR) + y * ZM_RASTER_WIDTH;
}

/* Before line y's first pass: the row as the picture holds it (the D$ was flushed at the swap). */
static void check_row(int y) {
    memcpy(g_before[y], (const void*)row_of((uint32_t)y), ROW_BYTES);
    g_would[y] = 1;
}

static void check_end(long f) {
    uint32_t rows = 0, bad = 0;
    vseq_idle();
    zmv_flush_dcache(); /* the compositor wrote the rows behind the D$ */
    for (uint32_t y = 0; y < VD_LINES; y++) {
        if (!g_would[y]) continue;
        rows++, g_would[y] = 0;
        if (memcmp(g_before[y], (const void*)row_of(y), ROW_BYTES) && bad++ < 4)
            printf("ZM VCHK %ld row %lu differs\n", f, (unsigned long)y);
    }
    vplan.checked += rows, vplan.mismatched += bad;
    printf("ZM VCHK %ld %lu %lu\n", f, (unsigned long)rows, (unsigned long)bad);
}
#endif

/* vseq_decide: line y, as the frame's first layer reaches it. */
static int decide(int y) {
    int skip = vd_line(g_pic, (uint32_t)y);
    g_composited += !skip, g_decided++;
#ifdef ZM_VSEQ_CHECK
    if (skip) check_row(y);
    skip = 0;
#endif
    if (g_full) skip = 0;
    g_skip[y] = (uint8_t)skip;
    return skip;
}

int vplan_frame(struct w2c_env* e, unsigned enabled, int full) {
    g_t0 = board_cycles(), g_wait0 = vseq.swap_wait, g_plan_cycles = 0;
#ifdef ZM_NO_VPLAN /* the baseline: every line of every layer, the sequencer as it was */
    (void)e, (void)enabled, (void)full;
    return 1;
#endif
    g_timed = 1;
#ifndef ZM_VSEQ_CHECK /* a check plans every frame: what it checks is the plan */
    if (!va_plans()) { /* it does not pay here (vadapt.h): nothing compared, every line composited */
        vd_unknown();
        return 1;
    }
#endif
    vd_frame fr = {e->memory.data, (uint32_t)e->memory.size, enabled, vseq_rec.fill, vseq_rec.bg, vseq_rec.beam};
    zmv_flush_dcache(); /* plane rows the blitter wrote behind the D$, and the pictures' */
    uint32_t t0 = board_cycles();
    int handler = vd_plan(&fr);
    g_plan_cycles = board_cycles() - t0;
    vseq_wait_swap(); /* the back picture is now the one this frame builds */
    g_pic = (zmv_status() & ZMV_BIT(FRONT)) ? 0 : 1;
    g_full = full, g_composited = 0, g_decided = 0, g_planned = 1;
    vseq_skip = g_skip, vseq_decide = decide;
    return handler;
}

/* The rest of this frame composites every line; its skipped ones are not trusted (vdirty.h). */
void vplan_mask_moved(void) {
    vd_mask_moved();
    vseq_skip = NULL;
}

void vplan_end(long f) {
    uint32_t waited = vseq.swap_wait - g_wait0;
#ifndef ZM_BOARD /* the lines composited (a check or a hashed frame: would be), the plan's cost, the swap wait */
    printf("ZM VD %ld %d %lu %lu %d\n", f, g_planned ? g_composited : (int)VD_LINES, (unsigned long)g_plan_cycles,
           (unsigned long)waited, va.mode);
#endif
    if (g_timed) va_frame(board_cycles() - g_t0 - waited);
    g_timed = 0;
    if (!g_planned) return;
    g_planned = 0;
    vseq_skip = NULL, vseq_decide = NULL;
    if (g_decided != VD_LINES) vd_mask_moved(); /* no layer asked for every line: trust no row */
    vplan.lines += VD_LINES, vplan.skipped += VD_LINES - (uint32_t)g_composited;
#ifdef ZM_VSEQ_CHECK
    check_end(f);
#endif
    (void)f;
}

void vplan_overdrawn(uint32_t back_addr, uint32_t y0, uint32_t n) { vd_overdrawn(back_addr == ZM_FB0_ADDR ? 0 : 1, y0, n); }

void vplan_report(void) {
    printf("ZM VPLAN %lu %lu %lu %lu %lu %lu %lu\n", (unsigned long)vplan.lines, (unsigned long)vplan.skipped,
           (unsigned long)vd.frames, (unsigned long)vd.unknown, (unsigned long)vd.mask_moved,
           (unsigned long)va.off_frames, (unsigned long)va.switches);
#ifdef ZM_VSEQ_CHECK
    printf("ZM VCHK total %lu %lu\n", (unsigned long)vplan.checked, (unsigned long)vplan.mismatched);
#endif
}
