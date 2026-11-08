/* See bdesk.h. Only the frame's bookkeeping lives here: the picture is the scanout's. */
#include "bdesk.h"

#include "bmailbox.h" /* mb_presenting */
#include "vboard.h" /* zmv_status, ZMV_BIT */
#include "vseq.h"
#include "zm_memmap.h"

static volatile uint8_t* region(struct w2c_env* e) { return e->memory.data + ZM_HW_VIDEO_BASE; }

static int desk(struct w2c_env* e) { return region(e)[ZM_REG_RESOLUTION] == ZM_RES_DESK; }

void bdesk_boot(struct w2c_env* e) {
    w2c_machine_hwSetDeskAvailable(&e->machine, (zmv_status() & ZMV_BIT(DESK)) != 0);
}

int bdesk_clear(struct w2c_env* e) {
    if (!desk(e)) return 0;
    volatile uint32_t* frame = (volatile uint32_t*)(region(e) + ZM_REG_FRAME);
    *frame = *frame + 1; /* video.zig's clear() in desk mode; the snoop carries it to the compositor */
    return 1;
}

void bdesk_leave(struct w2c_env* e) {
    volatile uint32_t* frame = (volatile uint32_t*)(region(e) + ZM_REG_FRAME);
    *frame = *frame - 1; /* the compositor counts it again, and vseq_clear copies its count back */
    vseq_clear(e);
}

/* The browser's desk hash (docs/GEM_DESK_MODE.md §6): the tag, then the two halves in order. */
static void hash(struct w2c_env* e, sha256_ctx* h) {
    const uint8_t* pfb = e->memory.data + w2c_machine_hwPhysicalPtr(&e->machine);
    sha256_update(h, "desk", 4);
    for (uint32_t half = 0; half < 2; half++) {
        w2c_machine_hwRenderDesk(&e->machine, half);
        sha256_update(h, pfb, (size_t)ZM_DESK_WIDTH * (ZM_DESK_HEIGHT / 2) * 4);
    }
}

int bdesk_frame(struct w2c_env* e, sha256_ctx* h) {
    if (!desk(e)) return 0;
    if (h) hash(e, h);
    /* No pass waits for the swap, so this does: without it PRESENT would only keep `pending` set
     * and the frames would run unpaced (zm_video_out.v's swap is what holds them to the VBL). */
    vseq_wait_swap();
    mb_presenting();
    vseq_present();
    return 1;
}
