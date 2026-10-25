/* KOS's power-on on the board: bkos.h. No statics on the board (the sim's hashing has two): the
 * system image's data layout (host/mem_place.h) does not move; linked after fw.a as bbootsec.c. */
#include "bkos.h"

#include <stdio.h>

#include "bboard.h"
#include "bdisk.h"
#include "bmailbox.h"
#include "bplanes.h"
#include "csr_addr.h"
#include "disk.h"
#include "glass_cart.h"
#include "glass_map.h"
#include "sha256.h"
#include "vboard.h"
#include "vseq.h"
#include "zm_memmap.h"

#define KOS_AT (CART_CPU_BASE + DDR_CART_BYTES - KOS_BOOT_FROM_TOP)
#define CSR(name) (*(volatile uint32_t*)CSR_GLASS_##name##_ADDR)

/* rom/kos/kos.zig's: what boots. */
#define DEV_DESKTOP 0u
#define DEV_DRIVE_A 1u

/* ZM_KOS_POST (sim): the POST's frames when no glass wrote the words; the board's default is none. */
#ifndef ZM_KOS_POST
#define ZM_KOS_POST 0
#endif

_Static_assert(KOS_BOOT_FROM_TOP <= BOOTSEC_SKIP_FROM_TOP - 4, "the KOS words are over the skip word");
_Static_assert(KOS_BOOT_FROM_TOP - KOS_BOOT_WORDS * 4 >= CART_REQ_FROM_TOP, "the KOS words are over the request block");

static uint32_t kos_flags(void) {
    const volatile uint32_t* w = (const volatile uint32_t*)(uintptr_t)KOS_AT;
    if (w[0] == KOS_BOOT_MAGIC) return w[1];
    return (uint32_t)ZM_KOS_POST << KOS_POST_SHIFT;
}

uint32_t bkos_post_frames(void) { return kos_flags() >> KOS_POST_SHIFT & KOS_POST_MASK; }

void bkos_boot(struct w2c_env* e, int bootable) {
    uint32_t f = kos_flags(), present = host_disk.data != 0;
    uint32_t dev = present && bootable ? DEV_DRIVE_A : DEV_DESKTOP;
    w2c_rom_kosSetBoot(&e->rom, f & KOS_WARM, dev, present, w2c_machine_hwRamFree(&e->machine));
    w2c_machine_hwInit(&e->machine);
    printf("ZM KOS boot %lu %lu %lu %lu\n", (unsigned long)(f & KOS_WARM), (unsigned long)dev, (unsigned long)present,
           (unsigned long)bkos_post_frames());
}

/* Keys typed over the POST go nowhere: it has no key export (the glass skips it for a held key). */
static void drop_keys(void) {
    for (int n = 0; n < 64 && (CSR(KEY_VALID) & 1u); n++) CSR(KEY_POP) = 1u;
}

#if ZM_FRAMES
/* The sim hashes each POST frame as scene_hash.mjs --kos does: plane 0's PFB, then "off<p>". */
static sha256_ctx* g_h;
static struct w2c_env* g_e;
static void hash_plane(unsigned p, int on) {
    if (!on) {
        char off[16];
        sha256_update(g_h, off, (size_t)snprintf(off, sizeof off, "off%u", p));
        return;
    }
    vseq_idle();
    zmv_flush_dcache();
    struct w2c_env* e = g_e;
    sha256_update(g_h, e->memory.data + w2c_machine_hwPhysicalPtr(&e->machine),
                  w2c_machine_hwPhysWidth(&e->machine) * w2c_machine_hwPhysHeight(&e->machine) * 4);
}
#endif

/* bmain.c's frame() for the POST: kosTick, the clear, kosPostFrame, plane 0 composited whole. */
static int frame(struct w2c_env* e, unsigned planes, long f) {
    drop_keys();
    w2c_rom_kosTick(&e->rom);
    vseq_clear(e);
    int done = w2c_rom_kosPostFrame(&e->rom) != 0;
#if ZM_FRAMES
    sha256_ctx h;
    char hex[65];
    sha256_init(&h);
    g_h = &h, g_e = e;
    if (bplanes_run(e, 1u, planes, 0, 0, hash_plane)) vseq_mix_only();
    sha256_hex(&h, hex);
    printf("ZM KOSHASH %ld %s\n", f, hex);
#else
    (void)f;
    if (bplanes_run(e, 1u, planes, 0, bplanes_lm(), NULL)) vseq_mix_only();
#endif
    vseq_copper_end(1u);
    mb_presenting();
    vseq_present();
    return done;
}

void bkos_run(struct w2c_env* e, uint32_t post) {
    unsigned planes = w2c_machine_hwPlanesNumber(&e->machine);
    board_state(ZM_CART_RUNNING); /* the glass waits 10 s for it; the POST holds 3 (it paints its border) */
    w2c_rom_kosPostStart(&e->rom, post);
    long f = 1;
    while (!frame(e, planes, f)) f++;
    drop_keys();
    printf("ZM KOS post %ld\n", f);
}
