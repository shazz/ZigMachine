/* See vdirty.h. The geometry mirrors rtl/video/zm_video_plane.v (and video.zig's
 * renderPlane*): which lines a plane covers, which row of its buffer a line
 * fetches, and how many bytes. */
#include "vdirty.h"

#include <string.h>

#include "vdlist.h"
#include "vdrow.h"

#define H VD_LINES
#define ROWMAX VD_ROWMAX
#define VD_HOT 60 /* frames a fully redrawn plane's lines go uncompared (plan_plane) */
/* The break mutants (fpga/tests/test_vdirty.py, ZM_RTL_BREAK=1): each forgets one input,
 * and the native proof must then find a skipped row a full composite paints differently. */
#ifdef VD_BREAK_ROWS
#define ROW_MOVED(x) ((void)(x), 0)
#else
#define ROW_MOVED(x) (x)
#endif

typedef struct {
    uint8_t rows[ZM_NB_PLANES][H][ROWMAX]; /* first: 32-byte aligned rows (cmpcpy's blocks) */
    uint32_t pal[ZM_NB_PLANES][ZM_PAL_ENTRIES];
    uint32_t ver[H];      /* each line's input version */
    uint32_t built[2][H]; /* version + 1 each picture's row was built from, 0 = none */
    uint32_t bg[H];
    uint8_t beam[H];
    pcfg cfg[ZM_NB_PLANES];
    unsigned enabled;
    int fill, valid;              /* valid: the copies below are the last frame's */
    uint8_t row_ok[ZM_NB_PLANES]; /* rows[p] and pal[p] hold plane p's last frame */
    uint8_t fresh[ZM_NB_PLANES];  /* this frame: rows[p] are refilled, every covered line is new */
    unsigned rows_on;             /* this frame: the planes whose rows vd_line compares */
    uint16_t moved_rows[ZM_NB_PLANES]; /* the last compared frame: covered rows that changed */
    uint8_t counted[ZM_NB_PLANES];     /* ... and it was one (not a refill) */
    uint8_t hot[ZM_NB_PLANES];         /* frames left in which plane p's covered lines are new, uncompared */
    const uint8_t* src[ZM_NB_PLANES][H]; /* this frame: where each line's fetch starts */
} vd_state;

static vd_state s __attribute__((aligned(32)));
vd_stats vd;

static void bump(uint32_t y0, uint32_t n) {
    for (uint32_t y = y0; y < y0 + n; y++) s.ver[y]++;
    vd.bumped += n;
}


void vd_unknown(void) {
    vd.frames++, vd.unknown++;
#ifdef VD_BREAK_UNKNOWN /* a frame composited without a plan leaves the versions as they were */
    return;
#endif
    s.rows_on = 0;
    bump(0, H);
    memset(s.built, 0, sizeof s.built);
    s.valid = 0;
}

void vd_mask_moved(void) {
    vd.mask_moved++;
    s.rows_on = 0;
    bump(0, H);
    memset(s.built, 0, sizeof s.built);
    s.valid = 0;
}

static void plan_bg(const vd_frame* fr) {
    for (uint32_t y = 0; y < H; y++) {
        uint32_t bg = fr->fill ? fr->bg[0] : fr->bg[y];
        uint8_t beam = fr->fill ? 0 : fr->beam[y];
#ifndef VD_BREAK_BG
        if (beam || s.beam[y] || bg != s.bg[y]) bump(y, 1);
#endif
        s.bg[y] = bg, s.beam[y] = beam;
    }
}

/* Plane p's palette against its copy; its rows are compared line by line (vd_line). */
static void plan_plane(const vd_frame* fr, int p, const pcfg* c) {
    const uint8_t* pal = fr->mem + ZM_HW_VIDEO_BASE + ZM_OFF_PAL + (uint32_t)p * ZM_PAL_BYTES;
    int moved = cmpcpy((uint8_t*)s.pal[p], pal, ZM_PAL_BYTES);
    vd.cmp_bytes += ZM_PAL_BYTES;
#ifdef VD_BREAK_PAL
    moved = 0;
#endif
    /* A plane at least 3/4 of whose covered rows moved in its last compared frame is redrawn
     * whole: for
     * VD_HOT frames its covered lines are new without comparing them (the cost that kept the plan
     * OFF), as a handler plane's are, and its border lines can still be skipped. Then one refill and
     * one compared frame decide again. */
    if (s.counted[p] && s.moved_rows[p] * 4u >= c->rows * 3u) s.hot[p] = VD_HOT;
    s.moved_rows[p] = 0, s.counted[p] = 0;
    if (s.hot[p]) {
        s.hot[p]--, s.row_ok[p] = 0;
#ifndef VD_BREAK_HOT
        bump(c->oy, c->rows);
#endif
        return;
    }
    if (moved || !s.row_ok[p]) bump(c->oy, c->rows);
    s.fresh[p] = !s.row_ok[p], s.row_ok[p] = 1, s.rows_on |= 1u << p;
    s.counted[p] = !s.fresh[p];
}

/* The last enabled plane, if it has an HBL handler: its stores land between its
 * own passes, after every other plane's, so only its covered lines are new (its
 * geometry is latched before its first handler runs). A handler plane below
 * another: what it stores reaches the planes above, whose lines are unknown. */
static int handler_plane(const vd_frame* fr) {
    int h = -1, last = -1;
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (!((fr->enabled >> p) & 1)) continue;
        if (h < 0 && rd(fr, ZM_REG_FB_HBL_ID + 2u * (uint32_t)p, 2)) h = p;
        last = p;
    }
    return h < 0 ? -1 : h == last ? h : -2;
}

int vd_plan(const vd_frame* fr) {
    pcfg cur[ZM_NB_PLANES];
    memset(cur, 0, sizeof cur);
    s.rows_on = 0;
    int h = handler_plane(fr);
    if (h == -2) return vd_unknown(), 1;
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (!((fr->enabled >> p) & 1)) continue;
        int ok = geom(fr, p, &cur[p]);
        for (uint32_t y = cur[p].oy; ok && p != h && y < cur[p].oy + cur[p].rows; y++)
            ok = (s.src[p][y] = fetch(fr, p, &cur[p], y)) != 0;
        if (!ok) return vd_unknown(), h >= 0;
    }
    vd.frames++;
    if (!s.valid || fr->enabled != s.enabled || fr->fill != s.fill || memcmp(cur, s.cfg, sizeof cur)) {
        bump(0, H);
        memset(s.row_ok, 0, sizeof s.row_ok);
    }
    plan_bg(fr);
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (((fr->enabled >> p) & 1) && p != h) plan_plane(fr, p, &cur[p]);
        else s.row_ok[p] = 0;
    }
#ifndef VD_BREAK_HANDLER
    if (h >= 0) bump(cur[h].oy, cur[h].rows);
#endif
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) /* a copper list that changed (vdlist.h) */
        if (((fr->enabled >> p) & 1) && vdl_moved(fr, p)) bump(cur[p].oy, cur[p].rows);
    memcpy(s.cfg, cur, sizeof cur);
    s.enabled = fr->enabled, s.fill = fr->fill, s.valid = 1;
    return h >= 0;
}

int vd_line(int pic, uint32_t y) {
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        const pcfg* c = &s.cfg[p];
        if (!((s.rows_on >> p) & 1) || y < c->oy || y >= c->oy + c->rows) continue;
        vd.cmp_bytes += c->len;
        int moved = ROW_MOVED(cmpcpy(s.rows[p][y], s.src[p][y], c->len));
        s.moved_rows[p] += (uint16_t)moved;
        if (moved || s.fresh[p]) bump(y, 1);
    }
    int skip = s.built[pic][y] == s.ver[y] + 1;
    s.built[pic][y] = s.ver[y] + 1;
#ifdef VD_BREAK_PICTURE /* one picture, not two: a row is trusted one frame after it changed */
    s.built[!pic][y] = s.ver[y] + 1;
#endif
    return skip;
}

void vd_overdrawn(int pic, uint32_t y0, uint32_t n) {
#ifdef VD_BREAK_OVERDRAWN
    return;
#endif
    for (uint32_t y = y0; y < y0 + n && y < H; y++) s.built[pic][y] = 0;
}
