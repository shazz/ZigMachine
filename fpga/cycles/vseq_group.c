/* Line-major groups (vseq.h vseq_group; fpga/PLANES_PLAN.md §3, decisions.md 2026-10-18).
 *
 * Plane-major, a plane's 280 passes each load the PFB row and the picture's row from DDR and
 * store them back, so a line composited by N planes moves its rows N times. Between the passes of
 * planes that have no HBL handler and follow each other, no cart code runs: every pass reads what
 * frame() (or the last handler below them) left, in either order, and LATCH takes the same
 * registers. So those planes run line by line here, the rows staying in the compositor's line
 * buffer and accumulator: one row load and one row store a line for the whole group
 * (zm_video_pass.v `hold` / `keep`), and none of the PFB row when the group is the frame's top
 * layer (`nopfb`: the picture is what is shown; nothing reads this frame's PFB after it). */
#include "vboard.h"
#include "vseq.h"
#include "vseq_wait.h"
#include "zm_memmap.h"

/* Plane p's pass of line y in group g: the lowest loads (or, as the first layer, fills) and folds
 * first; the others go on from it (`hold`); all but the top hand on to the next (`keep`). */
static void group_pass(unsigned g, int p, int top, int y, int first, int nopfb) {
    int low = !(g & ((1u << p) - 1u));
    int ext = (low ? 0 : ZMV_HOLD) | (p != top ? ZMV_KEEP : 0) | (p == top && nopfb ? ZMV_NOPFB : 0);
    vseq_issue(ZMV_PLANE, p, y, 1, first && low, first && low && vseq_fill(), ext);
}

void vseq_group(struct w2c_env* e, unsigned g, int first, int nopfb) {
    (void)e; /* no handler runs in a group */
    int low = __builtin_ctz(g), top = 31 - __builtin_clz(g);
    if (first) vseq_wait_swap();
    for (int p = low; p <= top; p++)
        if ((g >> p) & 1) vseq_latch(p);
    /* As vseq.c's layer(): the first layer decides each line while the line before composites. */
    int ask = first && vseq_decide, next = ask ? decide(0) : 0;
    for (int y = 0; y < (int)ZM_RASTER_HEIGHT; y++) {
        int skip = ask ? next : vseq_skip && vseq_skip[y];
        if (!skip) group_pass(g, low, top, y, first, nopfb);
        if (ask && y + 1 < (int)ZM_RASTER_HEIGHT) next = decide(y + 1);
        for (int p = low + 1; !skip && p <= top; p++)
            if ((g >> p) & 1) group_pass(g, p, top, y, first, nopfb);
    }
}
