/* The pointer's box (glass/src/map_cart.zig VBOX_*): where the cart's picture is, so glass stops
 * the pointer there. Matt, 9 Nov: GEM's arrow must not go into the borders; pt2-clone and
 * klystrack draw a smaller picture centred in a 400x280 plane and their cursor is drawn only over
 * it, so a pointer held to the plane vanished past the picture. The cart's own rectangle
 * (env.hostPointerBox, the SDL layer) wins; without one, the union of the enabled planes'
 * rectangles. Header-only so tests/tb/ptrbox_test.c runs it on the host. */
#ifndef ZM_BPTRBOX_H
#define ZM_BPTRBOX_H

#include <stdint.h>

#include "glass_cart.h"
#include "vwhole.h"

_Static_assert(ZM_RASTER_WIDTH <= VBOX_FIELD_MASK && ZM_RASTER_HEIGHT <= VBOX_FIELD_MASK,
               "the raster does not fit the box words' fields");

typedef struct { uint32_t x0, y0, x1, y1; } bptrbox_rect; /* raster pixels, ends exclusive */

static inline uint32_t bptrbox_xword(bptrbox_rect r) { return VBOX_X_TAG | r.x0 | r.x1 << VBOX_HI_SHIFT; }
static inline uint32_t bptrbox_yword(bptrbox_rect r) { return VBOX_Y_TAG | r.y0 | r.y1 << VBOX_HI_SHIFT; }

/* The planes in `on` (bit p: plane p enabled) with their FB_MODE and FB_STRIDE. No plane enabled
 * draws nothing to aim at: the whole raster, never a box that traps the pointer. */
static inline bptrbox_rect bptrbox_planes(unsigned on, const uint8_t mode[4], const uint16_t stride[4]) {
    bptrbox_rect r = {ZM_RASTER_WIDTH, ZM_RASTER_HEIGHT, 0, 0};
    for (int p = 0; p < 4; p++) {
        if (!((on >> p) & 1u)) continue;
#ifndef BPTRBOX_BREAK_WINDOW /* tests/test_board_ptrbox.py's mutant (ZM_RTL_BREAK=1): f897cb53's window */
        int whole = vplane_whole(mode[p], stride[p]);
#else
        int whole = 0;
#endif
        uint32_t bx = whole ? 0 : ZM_RASTER_BORDER_X, by = whole ? 0 : ZM_RASTER_BORDER_Y;
        uint32_t ex = whole ? ZM_RASTER_WIDTH : ZM_RASTER_BORDER_X + ZM_RASTER_VIS_WIDTH;
        uint32_t ey = whole ? ZM_RASTER_HEIGHT : ZM_RASTER_BORDER_Y + ZM_RASTER_VIS_HEIGHT;
        if (bx < r.x0) r.x0 = bx;
        if (by < r.y0) r.y0 = by;
        if (ex > r.x1) r.x1 = ex;
        if (ey > r.y1) r.y1 = ey;
    }
    if (r.x1 == 0) r = (bptrbox_rect){0, 0, ZM_RASTER_WIDTH, ZM_RASTER_HEIGHT};
    return r;
}

static inline uint32_t bptrbox_clip(int64_t v, uint32_t end) { return v < 0 ? 0 : v > (int64_t)end ? end : (uint32_t)v; }

/* env.hostPointerBox(x0, y0, x1, y1): the cart's picture in pointer() coordinates (the visible
 * window's origin, medium-res x, negative over the borders, ends exclusive), as i32. Into the
 * raster and clipped to it; 0 when nothing of it is left (the planes decide then). */
static inline int bptrbox_cart(uint32_t x0, uint32_t y0, uint32_t x1, uint32_t y1, bptrbox_rect* out) {
    bptrbox_rect r = {
        bptrbox_clip((int64_t)(int32_t)x0 + ZM_RASTER_BORDER_X, ZM_RASTER_WIDTH),
        bptrbox_clip((int64_t)(int32_t)y0 + ZM_RASTER_BORDER_Y, ZM_RASTER_HEIGHT),
        bptrbox_clip((int64_t)(int32_t)x1 + ZM_RASTER_BORDER_X, ZM_RASTER_WIDTH),
        bptrbox_clip((int64_t)(int32_t)y1 + ZM_RASTER_BORDER_Y, ZM_RASTER_HEIGHT),
    };
    if (r.x0 >= r.x1 || r.y0 >= r.y1) return 0;
    *out = r;
    return 1;
}

#endif
