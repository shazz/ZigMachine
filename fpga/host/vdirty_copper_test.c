/* The copper case the carts do not reach yet (host/vdirty_copper.h): a STATIC copper list on a
 * static picture, with one row below it that changes every frame. The planner skips the lines
 * whose rows and list did not change; on the board a skipped line takes no PLANE pass, so its
 * record is never applied, and the pass of the changed row below finds a record for a line already
 * passed and STOPS the list (rtl/video/zm_video_copper.v, SEL: c_hy < line). The browser applies
 * every record (machine/copper.zig). So a skipped line must never hold a record.
 *
 * One normal plane, records on raster lines 100 and 150 (an HSCROLL each), row 160 (raster line 200)
 * rewritten every frame. Runs the board's planner (cycles/vdirty.c) for FRAMES frames and counts
 * the skipped lines that hold a record; prints "VDCOPPER skipped S recskip R", exit 1 if R.
 * VD_BREAK=RECORDS builds the planner without the rule (tests/test_vdirty.py's break test). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vdirty.h"
#include "vdirty_copper.h"

#define FRAMES 12
#define PLANE_AT (ZM_OFF_VRAM + 0x8000u) /* the plane's buffer, region offset */
#define LIST_V 1u                        /* the list at OFF_VRAM + 16 */

static void w16(uint8_t* r, uint32_t o, uint32_t v) { r[o] = (uint8_t)v, r[o + 1] = (uint8_t)(v >> 8); }
static void w32(uint8_t* r, uint32_t o, uint32_t v) { w16(r, o, v & 0xFFFFu), w16(r, o + 2, v >> 16); }

/* HEAD line, n=1 | REG HSCROLL of plane 0 (a per-line shift, as a wobble keeps it); then the end
 * HEAD. A list the planner compares word for word (cycles/vdlist.h vdl_measure). */
static void list(uint8_t* r) {
    uint32_t at = ZM_OFF_VRAM + 16u * LIST_V;
    const uint32_t lines[2] = {100, 150};
    for (int i = 0; i < 2; i++, at += 8) {
        w32(r, at, 0xF0000000u | lines[i] << 19 | 1u);
        w32(r, at + 4, 0x20000000u | (uint32_t)ZM_REG_HSCROLL << 20 | (uint32_t)(i + 1));
    }
    w32(r, at, 0xF0000000u | 511u << 19);
}

int main(void) {
    uint32_t size = ZM_HW_VIDEO_BASE + PLANE_AT + ZM_WIDTH * ZM_HEIGHT + 4096;
    uint8_t* mem = calloc(1, size);
    if (!mem) return 2;
    uint8_t* r = mem + ZM_HW_VIDEO_BASE;
    r[ZM_REG_FB_MODE] = 0;
    w16(r, ZM_REG_FB_STRIDE, ZM_WIDTH);
    w32(r, ZM_REG_FB_BASE, PLANE_AT);
    w16(r, ZM_REG_FB_COPPER, LIST_V);
    list(r);
    uint32_t bg = 0, skipped = 0, recskip = 0;
    uint8_t beam = 0, rec[ZM_RASTER_HEIGHT];
    for (int f = 1; f <= FRAMES; f++) {
        memset(r + PLANE_AT + 160u * ZM_WIDTH, f, ZM_WIDTH); /* raster line 200 changes */
        vd_frame fr = {mem, size, 1u, 1, &bg, &beam};
        vd_plan(&fr);
        vdc_records(r, 1u, rec);
        for (uint32_t y = 0; y < VD_LINES; y++) {
            int skip = vd_line(f & 1, y);
            skipped += (uint32_t)skip, recskip += (uint32_t)(skip && rec[y]);
        }
    }
    printf("VDCOPPER skipped %u recskip %u\n", (unsigned)skipped, (unsigned)recskip);
    free(mem);
    return recskip != 0;
}
