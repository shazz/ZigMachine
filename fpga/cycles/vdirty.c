/* See vdirty.h. The geometry mirrors rtl/video/zm_video_plane.v (and video.zig's
 * renderPlane*): which lines a plane covers, which row of its buffer a line
 * fetches, and how many bytes. */
#include "vdirty.h"

#include <string.h>

#define H VD_LINES
#define ROWMAX ZM_RASTER_WIDTH /* the longest fetch a comparable line makes (medium overscan) */
/* The break mutants (fpga/tests/test_vdirty.py, ZM_RTL_BREAK=1): each forgets one input,
 * and the native proof must then find a skipped row a full composite paints differently. */
#ifdef VD_BREAK_ROWS
#define ROW_MOVED(x) ((void)(x), 0)
#else
#define ROW_MOVED(x) (x)
#endif
enum { K_NORMAL = 0, K_FS = 1, K_SCROLL = 2, K_MED = 3, K_OVS = 4 };

typedef struct {
    uint8_t kind, res;
    uint16_t stride, hs, len, oy, rows; /* stride, hs: fullscreen only (they place the columns) */
} pcfg;

typedef struct {
    uint32_t ver[H];      /* each line's input version */
    uint32_t built[2][H]; /* version + 1 each picture's row was built from, 0 = none */
    uint32_t bg[H];
    uint8_t beam[H];
    pcfg cfg[ZM_NB_PLANES];
    unsigned enabled;
    int fill, valid;              /* valid: the copies below are the last frame's */
    uint8_t row_ok[ZM_NB_PLANES]; /* rows[p] and pal[p] hold plane p's last frame */
    uint32_t pal[ZM_NB_PLANES][ZM_PAL_ENTRIES];
    uint8_t rows[ZM_NB_PLANES][H][ROWMAX];
} vd_state;

static vd_state s;
vd_stats vd;

static uint32_t rd(const vd_frame* fr, uint32_t off, int n) {
    const uint8_t* b = fr->mem + ZM_HW_VIDEO_BASE + off;
    return n == 1 ? b[0] : n == 2 ? (uint32_t)(b[0] | b[1] << 8) : (uint32_t)(b[0] | b[1] << 8 | b[2] << 16 | (uint32_t)b[3] << 24);
}

static void bump(uint32_t y0, uint32_t n) {
    for (uint32_t y = y0; y < y0 + n; y++) s.ver[y]++;
    vd.bumped += n;
}

/* Plane p's geometry (zm_video_plane.v's decode); 0 if its lines cannot be compared. */
static int geom(const vd_frame* fr, int p, pcfg* c) {
    uint32_t mode = rd(fr, ZM_REG_FB_MODE + (uint32_t)p, 1), stride = rd(fr, ZM_REG_FB_STRIDE + 2u * (uint32_t)p, 2);
    uint32_t k = mode >= 1 && mode <= 4 ? mode : stride == ZM_STRIDE_FULLSCREEN ? K_FS : K_NORMAL;
    int ovm = stride >= ZM_RASTER_WIDTH, phys = k == K_FS || k == K_OVS || (k == K_MED && ovm);
    uint32_t res = k == K_MED ? rd(fr, ZM_REG_RESOLUTION, 1) : 0, med = res == ZM_RES_MEDIUM;
    uint32_t len = k == K_FS ? stride : k == K_MED ? (med ? (ovm ? 800u : 640u) : (ovm ? 400u : 320u)) : ZM_WIDTH;
    memset(c, 0, sizeof *c);
    c->kind = (uint8_t)k, c->res = (uint8_t)res, c->len = (uint16_t)len;
    c->oy = phys ? 0 : ZM_RASTER_BORDER_Y, c->rows = phys ? H : ZM_HEIGHT;
    if (k == K_FS) c->stride = (uint16_t)stride, c->hs = (uint16_t)rd(fr, ZM_REG_HSCROLL + 2u * (uint32_t)p, 2);
    return k != K_OVS && len > 0 && len <= ROWMAX;
}

/* Where line y's fetch starts in the cart's memory; 0 if outside it. */
static const uint8_t* fetch(const vd_frame* fr, int p, const pcfg* c, uint32_t y) {
    uint64_t row = y - c->oy, stride = rd(fr, ZM_REG_FB_STRIDE + 2u * (uint32_t)p, 2);
    uint64_t sc = c->kind == K_SCROLL ? rd(fr, ZM_REG_HSCROLL + 2u * (uint32_t)p, 2) : 0;
    uint64_t at = (uint64_t)ZM_HW_VIDEO_BASE + rd(fr, ZM_REG_FB_BASE + 4u * (uint32_t)p, 4) + row * stride + sc;
    return at + c->len <= fr->mem_size ? fr->mem + at : 0;
}

/* dst := src; whether they differed. Aligned rows go 32 bytes at a time into
 * registers: the board's D$ is direct-mapped, and the source and its copy can
 * share a set, so word-by-word they would evict each other on every load. */
static int cmpcpy(uint8_t* dst, const uint8_t* src, uint32_t n) {
    if (((uintptr_t)src | (uintptr_t)dst | n) & 31) {
        if (!memcmp(dst, src, n)) return 0;
        memcpy(dst, src, n);
        return 1;
    }
    const uint32_t* a = (const uint32_t*)src;
    uint32_t* b = (uint32_t*)dst;
    for (uint32_t i = 0; i < n / 4; i += 8) {
        uint32_t a0 = a[i], a1 = a[i + 1], a2 = a[i + 2], a3 = a[i + 3];
        uint32_t a4 = a[i + 4], a5 = a[i + 5], a6 = a[i + 6], a7 = a[i + 7];
        if ((a0 ^ b[i]) | (a1 ^ b[i + 1]) | (a2 ^ b[i + 2]) | (a3 ^ b[i + 3]) | (a4 ^ b[i + 4]) | (a5 ^ b[i + 5]) |
            (a6 ^ b[i + 6]) | (a7 ^ b[i + 7])) {
            memcpy(b + i, a + i, n - 4 * i);
            return 1;
        }
    }
    return 0;
}

void vd_unknown(void) {
    vd.frames++, vd.unknown++;
    bump(0, H);
    memset(s.built, 0, sizeof s.built);
    s.valid = 0;
}

void vd_mask_moved(void) {
    vd.mask_moved++;
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

/* Plane p's palette and the rows it fetches, against their copies. */
static void plan_plane(const vd_frame* fr, int p, const pcfg* c, const uint8_t* src[H]) {
    const uint8_t* pal = fr->mem + ZM_HW_VIDEO_BASE + ZM_OFF_PAL + (uint32_t)p * ZM_PAL_BYTES;
    int moved = cmpcpy((uint8_t*)s.pal[p], pal, ZM_PAL_BYTES);
#ifdef VD_BREAK_PAL
    moved = 0;
#endif
    if (moved || !s.row_ok[p]) bump(c->oy, c->rows);
    for (uint32_t y = c->oy; y < c->oy + c->rows; y++)
        if (ROW_MOVED(cmpcpy(s.rows[p][y], src[y], c->len)) && s.row_ok[p]) bump(y, 1);
    s.row_ok[p] = 1;
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
    static const uint8_t* src[ZM_NB_PLANES][H];
    pcfg cur[ZM_NB_PLANES];
    memset(cur, 0, sizeof cur);
    int h = handler_plane(fr);
    if (h == -2) return vd_unknown(), 1;
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (!((fr->enabled >> p) & 1)) continue;
        int ok = geom(fr, p, &cur[p]);
        for (uint32_t y = cur[p].oy; ok && p != h && y < cur[p].oy + cur[p].rows; y++)
            ok = (src[p][y] = fetch(fr, p, &cur[p], y)) != 0;
        if (!ok) return vd_unknown(), h >= 0;
    }
    vd.frames++;
    if (!s.valid || fr->enabled != s.enabled || fr->fill != s.fill || memcmp(cur, s.cfg, sizeof cur)) {
        bump(0, H);
        memset(s.row_ok, 0, sizeof s.row_ok);
    }
    plan_bg(fr);
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (((fr->enabled >> p) & 1) && p != h) plan_plane(fr, p, &cur[p], src[p]);
        else s.row_ok[p] = 0;
    }
#ifndef VD_BREAK_HANDLER
    if (h >= 0) bump(cur[h].oy, cur[h].rows);
#endif
    memcpy(s.cfg, cur, sizeof cur);
    s.enabled = fr->enabled, s.fill = fr->fill, s.valid = 1;
    return h >= 0;
}

int vd_target(int pic, uint8_t skip[VD_LINES]) {
    int n = 0;
    for (uint32_t y = 0; y < H; y++) {
        skip[y] = s.built[pic][y] == s.ver[y] + 1;
        n += !skip[y];
        s.built[pic][y] = s.ver[y] + 1;
#ifdef VD_BREAK_PICTURE /* one picture, not two: a row is trusted one frame after it changed */
        s.built[!pic][y] = s.ver[y] + 1;
#endif
    }
    return n;
}

void vd_overdrawn(int pic, uint32_t y0, uint32_t n) {
#ifdef VD_BREAK_OVERDRAWN
    return;
#endif
    for (uint32_t y = y0; y < y0 + n && y < H; y++) s.built[pic][y] = 0;
}
