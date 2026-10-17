/* See bcursor.h. The arrow is TOS's ARROW mouse form (16x16, hot spot 0,0): the mask in
 * white, the data in black. A bit is one ST pixel: two raster pixels wide in low resolution
 * (320 pixels doubled across the raster's 640), one in medium, as TOS draws it in each.
 * The picture is rebuilt from the planes every frame, so nothing needs saving under it. */
#include "bcursor.h"

#include "glass_map.h" /* PTR_*: the pointer word */
#include "host.h"      /* host_input: does this cart take the mouse */
#include "vboard.h"    /* zmv_status, ZMV_BIT */
#include "vseq.h"
#include "zm_memmap.h"
#include "bmailbox.h" /* the two pictures */

static const uint16_t MASK[16] = {0xC000, 0xE000, 0xF000, 0xF800, 0xFC00, 0xFE00, 0xFF00, 0xFF80,
                                  0xFFC0, 0xFFE0, 0xFE00, 0xEF00, 0xCF00, 0x8780, 0x0780, 0x0380};
static const uint16_t DATA[16] = {0x0000, 0x4000, 0x6000, 0x7000, 0x7800, 0x7C00, 0x7E00, 0x7F00,
                                  0x7F80, 0x7C00, 0x6C00, 0x4600, 0x0600, 0x0300, 0x0300, 0x0000};

#define WHITE 0x00FFFFFFu /* {0,B,G,R} */
#define BLACK 0x00000000u

/* GEM starts with the arrow mid-screen, before the mouse has moved. */
static uint32_t g_x = PTR_WIDTH / 2, g_y = ZM_RASTER_HEIGHT / 2 - ZM_RASTER_BORDER_Y;

void bcursor_track(uint32_t ptr) {
    g_x = (ptr >> PTR_X_SHIFT) & PTR_COORD_MASK;
    g_y = (ptr >> PTR_Y_SHIFT) & PTR_COORD_MASK;
}

static void row(volatile uint32_t* line, uint32_t x0, uint32_t w, uint16_t mask, uint16_t data) {
    for (uint32_t i = 0; i < 16 * w && x0 + i < ZM_RASTER_WIDTH; i++) {
        uint16_t bit = (uint16_t)(0x8000u >> (i / w));
        if (mask & bit) line[x0 + i] = (data & bit) ? BLACK : WHITE;
    }
}

void bcursor_draw(void) {
    if (!host_input.pointer) return;
    vseq_idle(); /* every row of the picture is in memory before the arrow goes over it */
    /* FRONT is the picture on screen; the one being completed is the other (mb_presenting). */
    uint32_t back = (zmv_status() & ZMV_BIT(FRONT)) ? ZM_FB0_ADDR : ZM_FB1_ADDR;
    volatile uint32_t* pic = (volatile uint32_t*)(uintptr_t)back;
    uint32_t x0 = g_x + ZM_RASTER_BORDER_X, y0 = g_y + ZM_RASTER_BORDER_Y;
    uint32_t w = vseq_plane_mode(0) == ZM_FB_MODE_MEDIUM ? 1 : 2; /* GEM's desktop is plane 0 */
    for (uint32_t r = 0; r < 16 && y0 + r < ZM_RASTER_HEIGHT; r++)
        row(pic + (y0 + r) * ZM_RASTER_WIDTH, x0, w, MASK[r], DATA[r]);
}
