/* Line-major groups (vseq.h vseq_group; fpga/PLANES_PLAN.md §3, decisions.md 2026-10-18).
 *
 * Plane-major, a plane's 280 passes each load the PFB row and the picture's row from DDR and
 * store them back, so a line composited by N planes moves its rows N times. Between the passes of
 * planes that have no HBL handler and follow each other, no cart code runs: every pass reads what
 * frame() (or the last handler below them) left, in either order, and LATCH takes the same
 * registers. So those planes run line by line here, the rows staying in the compositor's line
 * buffer and accumulator: one row load and one row store a line for the whole group
 * (zm_video_pass.v `hold` / `keep`), and none of the PFB row when the group is the frame's top
 * layer (`nopfb`: the picture is what is shown; nothing reads this frame's PFB after it).
 *
 * A PURE handler (vseq_plane_pure: it writes only its own plane's palette and bumps RES_FLICKER,
 * fpga/review/FRESCO_OPTIONS.md) may join a group too: it runs right before its plane's pass of
 * the line, as in video.zig, and nothing another plane's pass reads changes, but for RES_FLICKER,
 * which is one register for every plane. An overscan pass flickers when RES_FLICKER differs from
 * what that plane's pass before saw (zm_video_plane.v), i.e. in video.zig's plane-major order when
 * ITS handler bumped it (renderPlaneOverscan's before/after). Here the other planes' handlers bump
 * it between, so the firmware reads it around each handler, as video.zig does, and stores the
 * value that gives the plane that answer before its pass; after the group, the count the handlers
 * made. Medium planes read RESOLUTION, which flickerBorder writes: no group with a handler has one. */
#include "vboard.h"
#include "vseq.h"
#include "vseq_wait.h"
#include "zm_memmap.h"

typedef struct {
    uint16_t hid, hpos, seen; /* the handler, its position; the RES_FLICKER the RTL last saw */
    uint32_t oy, rows;        /* the raster lines the handler runs on */
    int ov;                   /* an overscan plane: its pass compares RES_FLICKER */
} gplane;

static gplane g_p[ZM_NB_PLANES];
static int g_hbl;       /* the group has a handler: RES_FLICKER is the sequencer's until its end */
static int g_passed;    /* a pass was issued since the LATCHes: PAINTED speaks for it */
static uint16_t g_true; /* RES_FLICKER as video.zig has it: the handlers' own bumps */

int vseq_plane_pure(int p) {
#ifdef ZM_GROUP_HBL_ALL /* the experiment: every handler trusted (fpga/review/FRESCO_OPTIONS.md) */
    (void)p;
    return 1;
#else
    return !vseq_plane_handler(p);
#endif
}

int vseq_group_ok(unsigned g) {
    int hbl = 0, medium = 0;
    for (int p = 0; p < (int)ZM_NB_PLANES; p++)
        if ((g >> p) & 1) hbl |= vseq_plane_handler(p), medium |= vseq_plane_mode(p) == ZM_FB_MODE_MEDIUM;
    return !(hbl && medium);
}

/* Plane p's pass of line y in group g: the lowest loads (or, as the first layer, fills) and folds
 * first; the others go on from it (`hold`); all but the top hand on to the next (`keep`). */
static void group_pass(unsigned g, int p, int top, int y, int first, int nopfb) {
    int low = !(g & ((1u << p) - 1u));
    int ext = (low ? 0 : ZMV_HOLD) | (p != top ? ZMV_KEEP : 0) | (p == top && nopfb ? ZMV_NOPFB : 0);
    vseq_issue(ZMV_PLANE, p, y, 1, first && low, first && low && vseq_fill(), ext);
    g_passed = 1;
}

static void setup(unsigned g) {
    g_hbl = g_passed = 0, g_true = vseq_r16(ZM_REG_RES_FLICKER);
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (!((g >> p) & 1)) continue;
        gplane* q = &g_p[p];
        q->hid = vseq_r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p), q->hpos = vseq_r16(ZM_REG_FB_HBL_POS + 2u * (uint32_t)p);
        vseq_plane_lines(p, &q->oy, &q->rows);
        q->ov = vseq_plane_mode(p) == ZM_FB_MODE_OVERSCAN, q->seen = g_true;
        g_hbl |= q->hid != 0;
    }
}

/* Plane p's handler on line y if it covers it (after the pass before has read the state it may
 * change), then, unless the line is skipped, its pass, an overscan one seeing ITS flicker only. */
static void plane_line(struct w2c_env* e, unsigned g, int p, int top, int y, int skip, int first, int nopfb) {
    gplane* q = &g_p[p];
    int bumped = 0;
    if (q->hid && (uint32_t)y >= q->oy && (uint32_t)y < q->oy + q->rows) {
        if (g_passed) vseq_wait_painted();
        uint16_t before = vseq_r16(ZM_REG_RES_FLICKER);
        hbl(e, q->hid, (u32)p, (u32)y - q->oy, q->hpos);
        uint16_t now = vseq_r16(ZM_REG_RES_FLICKER);
        g_true += (uint16_t)(now - before), bumped = now != before;
    }
    if (skip) return;
#ifndef VSEQ_BREAK_FLICKER /* tests/test_vseq_group.py's mutant (ZM_RTL_BREAK=1): RES_FLICKER as the handlers left it */
    if (g_hbl && q->ov) {
        uint16_t want = (uint16_t)(q->seen + bumped);
        if (vseq_r16(ZM_REG_RES_FLICKER) != want) vseq_w16(ZM_REG_RES_FLICKER, want);
        q->seen = want;
    }
#else
    (void)bumped;
#endif
    group_pass(g, p, top, y, first, nopfb);
}

void vseq_group(struct w2c_env* e, unsigned g, int first, int nopfb) {
    int low = __builtin_ctz(g), top = 31 - __builtin_clz(g);
    setup(g);
    if (first) vseq_wait_swap();
    for (int p = low; p <= top; p++)
        if ((g >> p) & 1) vseq_latch(p);
    /* As vseq.c's layer(): the first layer decides each line while the line before composites. */
    int ask = first && vseq_decide, next = ask ? decide(0) : 0;
    for (int y = 0; y < (int)ZM_RASTER_HEIGHT; y++) {
        int skip = ask ? next : vseq_skip && vseq_skip[y];
        plane_line(e, g, low, top, y, skip, first, nopfb);
        if (ask && y + 1 < (int)ZM_RASTER_HEIGHT) next = decide(y + 1);
        for (int p = low + 1; p <= top; p++)
            if ((g >> p) & 1) plane_line(e, g, p, top, y, skip, first, nopfb);
    }
    if (g_hbl && vseq_r16(ZM_REG_RES_FLICKER) != g_true) vseq_w16(ZM_REG_RES_FLICKER, g_true);
}
