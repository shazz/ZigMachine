/* vdirty.c's row helpers, included once by it: a plane's geometry as zm_video_plane.v decodes it
 * (which lines it covers, which buffer row a line fetches, how many bytes), where that fetch starts,
 * and the 32-byte-at-a-time compare-and-copy of a row with its copy. */
#ifndef ZM_VDROW_H
#define ZM_VDROW_H

#include <stdint.h>
#include <string.h>

#include "vdirty.h"
#include "zm_memmap.h"

#define VD_ROWMAX ZM_RASTER_WIDTH /* the longest fetch a comparable line makes (medium overscan) */

enum { K_NORMAL = 0, K_FS = 1, K_SCROLL = 2, K_MED = 3, K_OVS = 4 };

typedef struct {
    uint8_t kind, res;
    uint16_t stride, hs, len, oy, rows; /* stride, hs: fullscreen only (they place the columns) */
} pcfg;

static uint32_t rd(const vd_frame* fr, uint32_t off, int n) {
    const uint8_t* b = fr->mem + ZM_HW_VIDEO_BASE + off;
    return n == 1 ? b[0] : n == 2 ? (uint32_t)(b[0] | b[1] << 8) : (uint32_t)(b[0] | b[1] << 8 | b[2] << 16 | (uint32_t)b[3] << 24);
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
    c->oy = phys ? 0 : ZM_RASTER_BORDER_Y, c->rows = phys ? VD_LINES : ZM_HEIGHT;
    if (k == K_FS) c->stride = (uint16_t)stride, c->hs = (uint16_t)rd(fr, ZM_REG_HSCROLL + 2u * (uint32_t)p, 2);
    return k != K_OVS && len > 0 && len <= VD_ROWMAX;
}

/* Where line y's fetch starts in the cart's memory; 0 if outside it. */
static const uint8_t* fetch(const vd_frame* fr, int p, const pcfg* c, uint32_t y) {
    uint64_t row = y - c->oy, stride = rd(fr, ZM_REG_FB_STRIDE + 2u * (uint32_t)p, 2);
    uint64_t sc = c->kind == K_SCROLL ? rd(fr, ZM_REG_HSCROLL + 2u * (uint32_t)p, 2) : 0;
    uint64_t at = (uint64_t)ZM_HW_VIDEO_BASE + rd(fr, ZM_REG_FB_BASE + 4u * (uint32_t)p, 4) + row * stride + sc;
    return at + c->len <= fr->mem_size ? fr->mem + at : 0;
}

/* dst := src; whether they differed. Word-aligned rows go 32 bytes at a time into
 * registers: the board's D$ is direct-mapped, and the source and its copy can
 * share a set, so word by word they would evict each other on every load. */
static int cmpcpy(uint8_t* dst, const uint8_t* src, uint32_t n) {
    if (((uintptr_t)src | (uintptr_t)dst | n) & 3) {
        if (!memcmp(dst, src, n)) return 0;
        memcpy(dst, src, n);
        return 1;
    }
    const uint32_t* a = (const uint32_t*)src;
    uint32_t* b = (uint32_t*)dst;
    uint32_t i = 0, nw = n / 4;
    for (; i + 8 <= nw; i += 8) {
        uint32_t a0 = a[i], a1 = a[i + 1], a2 = a[i + 2], a3 = a[i + 3];
        uint32_t a4 = a[i + 4], a5 = a[i + 5], a6 = a[i + 6], a7 = a[i + 7];
        __asm__ volatile("" ::: "memory"); /* the source's block is in registers before its copy is read */
        if ((a0 ^ b[i]) | (a1 ^ b[i + 1]) | (a2 ^ b[i + 2]) | (a3 ^ b[i + 3]) | (a4 ^ b[i + 4]) | (a5 ^ b[i + 5]) |
            (a6 ^ b[i + 6]) | (a7 ^ b[i + 7]))
            break;
    }
    for (; i < nw && a[i] == b[i]; i++) {
    }
    if (i == nw) return 0;
    memcpy(b + i, a + i, 4 * (nw - i));
    return 1;
}
#endif
