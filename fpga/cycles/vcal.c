/* The video probe's boot calibration (glass/src/map_cart.zig "VCAL"): what one row read and one
 * row write cost FRESCO on this board, measured, so the per-frame means (vstat.h) can be split
 * into row I/O and painting without an RTL counter.
 *
 * Run once from vstat_boot, after vseq_init and before the cart's first frame: MIX passes on
 * raster line 0, which read the PFB row (and the picture's), mix, and write the picture's row (and,
 * with `fill`, the PFB's). They leave line 0 of the PFB and of the back picture as they please:
 * frame 1 paints every line of both (its clear, then every line of the first layer; the dirty-line
 * planner trusts no row before its probe frames, vadapt.h), so nothing the cart sees changes. No
 * BG pass and no CLEAR: those would count a frame or write back BACKGROUND. */
#include <stdint.h>

#include "glass_cart.h"
#include "vboard.h"
#include "vstat.h"

#ifndef ZM_VCAL_BLOCK
#define ZM_VCAL_BLOCK ((volatile uint32_t*)(0x42000000u - VCAL_FROM_TOP))
#endif

static void until_ready(void) {
    while (!(zmv_status() & ZMV_BIT(READY))) {
    }
}

/* VCAL_REPS passes of one kind: the mean span (sys) and busy clocks (comp) into w[0], w[1]. */
static void kind(volatile uint32_t* w, int first, int fill) {
    uint32_t span = 0, comp = 0;
    for (uint32_t i = 0; i < VCAL_REPS; i++) {
        until_ready();
        uint32_t c0 = ZMV_REG(COMP_BUSY), t0 = board_cycles();
        zmv_cmd(ZMV_MIX, 0, 0, 1, first, fill);
        until_ready();
        span += board_cycles() - t0;
        comp += ZMV_REG(COMP_BUSY) - c0;
    }
    w[0] = span / VCAL_REPS, w[1] = comp / VCAL_REPS;
}

void vcal_run(void) {
    volatile uint32_t* b = ZM_VCAL_BLOCK;
    b[VC_MAGIC] = 0;
    kind(b + VC_MIX1, 1, 0);
    kind(b + VC_MIX2, 0, 0);
    kind(b + VC_FILL1, 1, 1);
    kind(b + VC_FILL2, 0, 1);
    b[VC_REPS] = VCAL_REPS;
    b[VC_MAGIC] = VCAL_MAGIC; /* last: a reader that sees it sees the rest */
}
