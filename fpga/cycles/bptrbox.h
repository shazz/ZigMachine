/* The pointer's box (glass/src/map_cart.zig VBOX_*): the union of the enabled planes' rectangles
 * on the raster, so glass stops the pointer where the cart draws. Matt, 9 Nov: GEM's arrow must
 * not go into the borders, but pt2-clone and klystrack draw over them (400x280 planes) and lost
 * their top and bottom rows when glass clamped every cart to the visible window.
 * Header-only so tests/tb/ptrbox_test.c runs it on the host. */
#ifndef ZM_BPTRBOX_H
#define ZM_BPTRBOX_H

#include <stdint.h>

#include "glass_cart.h"
#include "vwhole.h"

_Static_assert(ZM_RASTER_BORDER_X % VBOX_X_UNIT == 0 && ZM_RASTER_VIS_WIDTH % VBOX_X_UNIT == 0 &&
                   ZM_RASTER_WIDTH % VBOX_X_UNIT == 0, "a plane's x edge is off the box word's grid");
_Static_assert(ZM_RASTER_BORDER_Y % VBOX_Y_UNIT == 0 && ZM_RASTER_VIS_HEIGHT % VBOX_Y_UNIT == 0 &&
                   ZM_RASTER_HEIGHT % VBOX_Y_UNIT == 0, "a plane's y edge is off the box word's grid");
_Static_assert(ZM_RASTER_WIDTH / VBOX_X_UNIT <= VBOX_FIELD_MASK && ZM_RASTER_HEIGHT / VBOX_Y_UNIT <= VBOX_FIELD_MASK,
               "the raster does not fit the box word's fields");

static inline uint32_t bptrbox_pack(uint32_t x0, uint32_t y0, uint32_t x1, uint32_t y1) {
    return VBOX_TAG | (x0 / VBOX_X_UNIT) << VBOX_X0_SHIFT | (x1 / VBOX_X_UNIT) << VBOX_X1_SHIFT |
           (y0 / VBOX_Y_UNIT) << VBOX_Y0_SHIFT | (y1 / VBOX_Y_UNIT) << VBOX_Y1_SHIFT;
}

/* The word for the planes in `on` (bit p: plane p enabled) with their FB_MODE and FB_STRIDE. No
 * plane enabled draws nothing to aim at: the whole raster, never a box that traps the pointer. */
static inline uint32_t bptrbox_word(unsigned on, const uint8_t mode[4], const uint16_t stride[4]) {
    uint32_t x0 = ZM_RASTER_WIDTH, y0 = ZM_RASTER_HEIGHT, x1 = 0, y1 = 0;
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
        if (bx < x0) x0 = bx;
        if (by < y0) y0 = by;
        if (ex > x1) x1 = ex;
        if (ey > y1) y1 = ey;
    }
    if (x1 == 0) return bptrbox_pack(0, 0, ZM_RASTER_WIDTH, ZM_RASTER_HEIGHT);
    return bptrbox_pack(x0, y0, x1, y1);
}

#endif
