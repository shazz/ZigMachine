/* The copper half of the dirty-line proof (host/vdirty_main.c): the board's copper engine
 * (rtl/video/zm_video_copper.v) applies a plane's line record only when a PLANE pass of that line
 * is taken, and a pass that finds a record for a line already passed stops the list. The browser
 * (machine/copper.zig) applies every record. So a skipped line that holds a record of a list the
 * line's plane covers is where the two machines part: the list stops on the board, and every
 * later line of that plane takes the wrong palette (or HSCROLL, or FLICK).
 *
 * The full composite this proof compares with cannot see it (it applies every record), so the
 * proof counts those lines directly, walking each enabled plane's list as the machine does. */
#ifndef ZM_VDIRTY_COPPER_H
#define ZM_VDIRTY_COPPER_H

#include <stdint.h>
#include <string.h>

#include "zm_memmap.h"

static uint32_t vdc_word(const uint8_t* reg, uint32_t off) {
    return (uint32_t)(reg[off] | reg[off + 1] << 8 | reg[off + 2] << 16 | (uint32_t)reg[off + 3] << 24);
}

/* The raster lines plane p covers (cycles/vseq.c vseq_plane_lines). */
static void vdc_cover(const uint8_t* reg, int p, uint32_t* y0, uint32_t* y1) {
    uint8_t mode = reg[ZM_REG_FB_MODE + (uint32_t)p];
    uint16_t stride = (uint16_t)(reg[ZM_REG_FB_STRIDE + 2u * (uint32_t)p] | reg[ZM_REG_FB_STRIDE + 2u * (uint32_t)p + 1] << 8);
    int whole = mode == ZM_FB_MODE_FULLSCREEN || mode == ZM_FB_MODE_OVERSCAN;
    if (mode == ZM_FB_MODE_MEDIUM) whole = stride >= ZM_RASTER_WIDTH;
    else if (mode != ZM_FB_MODE_SCROLL && !whole) whole = stride == ZM_STRIDE_FULLSCREEN;
    *y0 = whole ? 0 : ZM_RASTER_BORDER_Y;
    *y1 = whole ? ZM_RASTER_HEIGHT : ZM_RASTER_BORDER_Y + ZM_HEIGHT;
}

/* rec[y] = 1 where an enabled plane's list holds a record for covered line y, up to where the
 * list would stop (a word that is no HEAD, a line not after the last, a body leaving VRAM). */
static void vdc_records(const uint8_t* reg, unsigned on, uint8_t rec[ZM_RASTER_HEIGHT]) {
    memset(rec, 0, ZM_RASTER_HEIGHT);
    const uint32_t end = ZM_OFF_VRAM + ZM_VRAM_BYTES;
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (!((on >> p) & 1)) continue;
        uint32_t v = (uint32_t)(reg[ZM_REG_FB_COPPER + 2u * (uint32_t)p] | reg[ZM_REG_FB_COPPER + 2u * (uint32_t)p + 1] << 8);
        uint32_t y0, y1, at = ZM_OFF_VRAM + 16u * v;
        int last = -1;
        vdc_cover(reg, p, &y0, &y1);
        while (v && at + 4 <= end) {
            uint32_t head = vdc_word(reg, at), line = (head >> 19) & 0x1FFu, n = head & 0x3FFu;
            if (head >> 28 != 0xFu || line == 511u || (int)line <= last || line < y0 || line >= y1) break;
            rec[line] = 1, last = (int)line;
            if (n > 253u || at + 4 + 4 * n > end) break;
            at += 4 + 4 * n;
        }
    }
}

#endif
