/* See bdesk.h. Only the frame's bookkeeping lives here: the picture is the scanout's. */
#include "bdesk.h"

#include "bmailbox.h" /* mb_presenting */
#include "glass_cart.h" /* VMODE_*: the mode word glass reads for the pointer */
#include "glass_map.h"  /* CART_CPU_BASE, DDR_CART_BYTES */
#include "host_desk.h"
#include "vboard.h" /* zmv_status, ZMV_BIT */
#include "vseq.h"
#include "zm_memmap.h"

#define VMODE_ADDR (CART_CPU_BASE + DDR_CART_BYTES - VMODE_FROM_TOP)
_Static_assert(KOS_FILE_FROM_TOP <= VMODE_FROM_TOP - 4, "the mode word is over the C: file block");
_Static_assert(VMODE_FROM_TOP <= KOS_CGEN_FROM_TOP - 4, "the mode word is over the C: generation word");

static uint32_t g_vmode; /* the word last stored: one store a change, not one a frame */
static uint32_t g_base0; /* plane 0's FB_BASE at the last desk frame: a change is a flip */

static volatile uint8_t* region(struct w2c_env* e) { return e->memory.data + ZM_HW_VIDEO_BASE; }

static int desk(struct w2c_env* e) { return region(e)[ZM_REG_RESOLUTION] == ZM_RES_DESK; }

/* Tell glass the cart's mode (map_cart.zig VMODE_*): the pointer is 640x480 at 1:1 in the desk. */
static void publish(int on) {
    uint32_t w = VMODE_TAG | (on ? VMODE_DESK : 0u);
    if (w == g_vmode) return;
    g_vmode = w;
    *(volatile uint32_t*)(uintptr_t)VMODE_ADDR = w;
}

void bdesk_boot(struct w2c_env* e) {
    w2c_machine_hwSetDeskAvailable(&e->machine, (zmv_status() & ZMV_BIT(DESK)) != 0);
    g_vmode = 0; /* a load zeroed the word: the first frame stores it */
    g_base0 = 0;
}

int bdesk_clear(struct w2c_env* e) {
    int on = desk(e);
    publish(on);
    if (!on) return 0;
    volatile uint32_t* frame = (volatile uint32_t*)(region(e) + ZM_REG_FRAME);
    *frame = *frame + 1; /* video.zig's clear() in desk mode; the snoop carries it to the compositor */
    return 1;
}

void bdesk_leave(struct w2c_env* e) {
    volatile uint32_t* frame = (volatile uint32_t*)(region(e) + ZM_REG_FRAME);
    *frame = *frame - 1; /* the compositor counts it again, and vseq_clear copies its count back */
    vseq_clear(e);
}

int bdesk_frame(struct w2c_env* e, sha256_ctx* h) {
    if (!desk(e)) return 0;
    if (h) host_desk_hash(e, h); /* the browser's rule (host/host_desk.h) */
    /* No pass waits for the swap, so this does: without it PRESENT would only keep `pending` set
     * and the frames would run unpaced (zm_video_out.v's swap is what holds them to the VBL). */
    vseq_wait_swap();
    mb_presenting();
    vseq_present();
    /* A flip (GEM's two desk buffers, rom/gem/desktop/deskflip.zig): the scanout takes the new
     * FB_BASE at the next VBL, and the cart's next frame draws into the buffer it just left. So
     * that frame starts after that VBL (the swap PRESENT asks for is taken at the same VBL), or a
     * frame that overran would draw over the picture still on the screen. */
    uint32_t base0 = *(volatile uint32_t*)(region(e) + ZM_REG_FB_BASE);
    if (base0 != g_base0) {
        g_base0 = base0;
        vseq_wait_swap();
    }
    return 1;
}
