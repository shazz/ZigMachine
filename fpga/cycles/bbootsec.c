/* A disk's executable boot sector on the board, before its cart: bbootsec.h. No statics: the
 * interpreter's state is on the stack for the phase only, so the system image's data layout
 * (and the D$ sets the hot data falls in, host/mem_place.h) does not move. */
#include "bbootsec.h"

#include <stdio.h>

#include "bboard.h"
#include "bdisk.h"
#include "bmailbox.h"
#include "bootsec.h"
#include "bplanes.h"
#include "csr_addr.h"
#include "disk.h"
#include "glass_cart.h"
#include "glass_map.h"
#include "vseq.h"
#include "zm_memmap.h"

#define SKIP_WORD (*(volatile uint32_t*)(uintptr_t)(CART_CPU_BASE + DDR_CART_BYTES - BOOTSEC_SKIP_FROM_TOP))
#define CSR(name) (*(volatile uint32_t*)CSR_GLASS_##name##_ADDR)

_Static_assert(BOOTSEC_SKIP_FROM_TOP < DISK_DESC_FROM_TOP - DISK_DESC_WORDS * 4 &&
                   BOOTSEC_SKIP_FROM_TOP > CART_REQ_FROM_TOP, "the skip word is over the descriptor or the request");

int bbootsec_wanted(void) {
#ifndef ZM_BOOTSEC
    return 0;
#else
    if (bdisk_role != BDISK_CART || SKIP_WORD == BOOTSEC_SKIP) return 0;
    return bootsec_executable(host_disk.data, host_disk.size);
#endif
}

/* A handler would be called into a cart not instantiated yet (in the browser, the sector has
 * no hblDispatch and the frame throws): the phase ends before the next pass could call one. */
static int hbl_set(struct w2c_env* e, unsigned planes) {
    const volatile uint16_t* r = (const volatile uint16_t*)(e->memory.data + ZM_HW_VIDEO_BASE);
    int any = r[ZM_REG_GLOBAL_HBL_ID / 2] != 0;
    for (unsigned p = 0; p < planes; p++) any |= r[ZM_REG_FB_HBL_ID / 2 + p] != 0;
    return any;
}

/* Keys typed over the sector go nowhere, as in the browser (the sector has no key export). */
static void drop_keys(void) {
    for (int n = 0; n < 64 && (CSR(KEY_VALID) & 1u); n++) CSR(KEY_POP) = 1u;
}

/* bmain.c's frame() for the sector: the clear, frame(dt) and pollCartRequest, then every plane
 * it enables composited whole (no dirty-line plan: the cart's starts fresh). 1 = it asked for
 * its cart (this frame is shown), 0 = go on, -1 = stop before showing anything. */
static int frame(struct w2c_env* e, bootsec_t* b, unsigned planes) {
    drop_keys();
    vseq_clear(e);
    int rc = bootsec_frame(b, 16.6f);
    unsigned on = 0;
    for (unsigned p = 0; rc >= 0 && p < planes; p++) on |= bootsec_plane_on(b, p) ? 1u << p : 0u;
    if (rc < 0 || b->st || hbl_set(e, planes)) return -1;
    vseq_wait_swap(); /* the back picture is free */
    if (bplanes_run(e, on, planes, 0, bplanes_lm(), NULL)) vseq_mix_only();
    vseq_copper_end(on);
    mb_presenting();
    vseq_present();
    return rc;
}

void bbootsec_run(struct w2c_env* e) {
    bootsec_t b; /* ~10 KB of the 1 MiB stack, for the phase only */
    struct w2c_machine* m = &e->machine;
    unsigned planes = w2c_machine_hwPlanesNumber(m);
    board_state(ZM_CART_RUNNING); /* the glass waits 10 s for it: the sector may hold 30 */
    w2c_machine_hwInit(m);        /* the browser: instantiate the sector, hwInit, boot() */
#ifdef ZM_BOARD
    *(volatile uint32_t*)(e->memory.data + ZM_HW_VIDEO_BASE + ZM_REG_BACKGROUND) = 0xFF000000u; /* bsys.c's */
#endif
    wint_status st = bootsec_start(&b, host_disk.data, e->memory.data, (uint32_t)e->memory.size,
                                   w2c_machine_hwVideoBase(m), NULL);
    printf("ZM BOOTSEC start %s %lu\n", bootsec_status(st), (unsigned long)b.w.steps);
    int rc = st || hbl_set(e, planes) ? -1 : 0;
    while (rc == 0) rc = frame(e, &b, planes);
    drop_keys();
    printf("ZM BOOTSEC end %lu %s %lu\n", (unsigned long)b.frames, bootsec_status(b.st), (unsigned long)b.w.steps);
}
