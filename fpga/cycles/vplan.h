/* The board's dirty-line sequencing (vplan.c): only the raster lines whose
 * inputs changed are composited again (vdirty.h decides which).
 *
 * In bmain.c's frame(), after cart.frame():
 *   vplan_frame      compare the inputs, wait for the swap, and point vseq_skip
 *                    at the lines the back picture already holds; returns 1 if
 *                    a plane has an HBL handler, and then bmain asks each plane
 *                    again where video.zig does (vplan_mask_moved if a handler
 *                    switched one: the plan is dropped, and every line is new);
 *   vplan_end        after the planes, before anything draws over the picture;
 *   vplan_overdrawn  bcursor.c drew rows of the back picture after the composite.
 *
 * ZM_VSEQ_CHECK: every line is composited all the same, and the rows the plan
 * would have skipped are compared with what the picture held before: "ZM VCHK"
 * per frame, and the totals at the end (vplan_report). */
#ifndef ZM_VPLAN_H
#define ZM_VPLAN_H

#include <stdint.h>

#include "host.h"

typedef struct {
    uint32_t lines, skipped; /* raster lines planned, and skipped */
    uint32_t checked, mismatched; /* ZM_VSEQ_CHECK: rows compared, rows that differed */
} vplan_stats;
extern vplan_stats vplan;

/* full: composite every line all the same (a sim frame whose PFB is hashed). */
int vplan_frame(struct w2c_env* e, unsigned enabled, int full);
void vplan_mask_moved(void);
void vplan_end(long f);
void vplan_overdrawn(uint32_t back_addr, uint32_t y0, uint32_t n);
void vplan_report(void);

#endif
