/* The debug mailbox (bmailbox.h). The CPU's D-cache is write-through, so every
 * store here reaches DDR at once; the ARM's `freeze` write is read past the
 * cache (flushed first), since nothing else would ever invalidate that line. */
#include "bmailbox.h"

#include "vboard.h"
#include "zm_memmap.h"

#define MB ((volatile uint32_t*)ZM_MB_ADDR)

void mb_init(uint32_t pfb, uint32_t pfb_w, uint32_t pfb_h) {
    for (int i = 0; i < MB_WORDS; i++) MB[i] = 0;
    MB[MB_VERSION] = ZM_MB_VERSION;
    MB[MB_FB0] = ZM_FB0_ADDR;
    MB[MB_FB1] = ZM_FB1_ADDR;
    MB[MB_PFB] = pfb;
    MB[MB_PFB_W] = pfb_w;
    MB[MB_PFB_H] = pfb_h;
    MB[MB_PIC_W] = ZM_RASTER_WIDTH;
    MB[MB_PIC_H] = ZM_RASTER_HEIGHT;
    MB[MB_CPU_BASE] = 0x40000000u;
    MB[MB_DDR_BASE] = 0x04000000u; /* soc/zm_hp.py DDR_BASE */
    MB[MB_MAGIC] = ZM_MB_MAGIC;    /* last: a reader that sees it sees the rest */
}

void mb_presenting(void) { MB[MB_PRESENTED] = (zmv_status() & ZMV_BIT(FRONT)) ? 0u : 1u; }

static uint32_t freeze_asked(void) {
    zmv_flush_dcache();
    return MB[MB_FREEZE];
}

void mb_frame_done(uint32_t frames) {
    MB[MB_FRAMES] = frames;
    if (!freeze_asked()) return;
    while (zmv_status() & ZMV_BIT(PENDING)) {
    } /* the presented picture is on screen */
    MB[MB_FRONT] = (zmv_status() & ZMV_BIT(FRONT)) ? 1u : 0u;
    MB[MB_FROZEN] = frames;
    while (freeze_asked()) {
    }
    MB[MB_FROZEN] = 0;
}
