/* KOS's power-on on the board (bkos.c): docs/ZIGTOS_BOOT.md, KOS = ZigTOS. What the browser
 * (docs/kos-boot.js), the native host (host/kos_host.c) and node (apps/scene_hash_kos.mjs) do
 * before drive A boots, from the same ROM exports (rom/kos/kos.zig):
 *
 *   kosSetBoot(kind, what boots, drive A full?, hwRamFree), hwInit, then the POST: kosPostFrame()
 *   on plane 0, composited whole, until it says done. Keys typed meanwhile are dropped.
 *
 * bmain.c's boot(): after bdisk_boot (the drive) and bdiskapp_boot (is the disk bootable?),
 * bkos_boot says how long (the glass's frames, none after a warm reset); with a POST, host_boot_machine, the compositor brought up,
 * bkos_run, then the boot sector (bbootsec.h) and the cart as before. Without one (a load that is
 * no reset, a glass before KOS), only the system variables are set, and nothing else changes.
 *
 * The glass's KOS boot words (glass/src/map_cart.zig KOS_BOOT_*) give the reset's kind and the
 * POST's length; a sim has no glass, so ZM_KOS_POST=n (board.mk) stands in for them.
 * Lines (sim): "ZM KOS boot <kind> <dev> <drive> <post>", "ZM KOS post <frames>". */
#ifndef ZM_BKOS_H
#define ZM_BKOS_H

#include <stdint.h>

#include "host.h"

/* After host_boot_machine(): the system variables, hwInit; the POST's frames (0: none, and none
 * after a warm reset: the ROM's kosPostFrames). */
uint32_t bkos_boot(struct w2c_env* e, int bootable);
/* After vseq_init(): the POST's frames, each a CART_BEAT from `beat` on (the glass counts them: a POST
 * is no hang); returns the last beat. */
uint32_t bkos_run(struct w2c_env* e, uint32_t post, uint32_t beat);

#endif
