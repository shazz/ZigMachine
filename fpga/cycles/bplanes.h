/* The board's plane phase (bmain.c frame(), after vplan_frame): each enabled plane in
 * machine/video.zig's order, its handler between its passes (vseq_plane), or, where that is exact,
 * line-major (vseq_group): every run of enabled planes that follow each other with no HBL handler
 * among them, since no cart code runs between their passes in either order (decisions.md
 * 2026-10-18, "Line-major groups"). A handler plane is plane-major (its handler may write what a
 * lower plane's pass reads: RESOLUTION, RES_FLICKER, a palette, the LFB at line y) unless its
 * handler is PURE (vseq_plane_pure: own palette and RES_FLICKER bumps only, vseq_group.c), which
 * only the ZM_GROUP_HBL_ALL experiment claims today (fpga/review/FRESCO_OPTIONS.md).
 *
 * Line-major runs on the board (ZM_BOARD) unless the ARM's switch word says plane-major
 * (bdiag.h DIAG_OPT_PLANE_MAJOR), and in a sim only with ZM_LINEMAJOR: a hashed frame is always
 * plane-major, since its PFB is hashed after each plane as apps/scene_hash.mjs does. A group that
 * is the frame's top layer stores no PFB row (nothing reads it after; DIAG_OPT_KEEP_PFB keeps it).
 *
 * ZM_LM_CHECK (sim): a hashed frame that groups cover whole (no plane handler, a fused clear) is
 * composited line-major first, its picture hashed, then plane-major as always: "ZM LMCHK f same|DIFFER"
 * and the totals at the end (bplanes_report). */
#ifndef ZM_BPLANES_H
#define ZM_BPLANES_H

#include <stdint.h>

#include "host.h"

/* A hashed frame's PFB bookkeeping: plane p composited (on) or skipped (off). NULL: not hashed. */
typedef void (*bplanes_hash)(unsigned p, int on);

/* Line-major is on for frames that are not hashed. */
int bplanes_lm(void);
/* The planes of [0, planes) that `on` (vplan_frame's answer) and, with `handler`, the cart's own
 * answer at each plane enable; returns 1 if none ran (the caller shows the clear: vseq_mix_only). */
int bplanes_run(struct w2c_env* e, unsigned on, unsigned planes, int handler, int lm, bplanes_hash hash);
/* ZM_LM_CHECK: before a hashed frame's planes, the line-major composite and its picture's hash;
 * after them, the plane-major picture's hash and the verdict. Nothing without ZM_LM_CHECK. */
void bplanes_check_pre(struct w2c_env* e, unsigned on, unsigned planes, int handler);
void bplanes_check_post(long f);
void bplanes_report(void);

#endif
