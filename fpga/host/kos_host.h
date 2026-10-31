/* The native host's --kos X.zmd|none [--post-frames N]: KOS's power-on (docs/ZIGTOS_BOOT.md), as
 * apps/scene_hash_kos.mjs runs it in node and docs/sealed-loader.js in the browser: the ROM's
 * POST on plane 0, then drive A decides: the disk's executable boot sector (then its cart, or the
 * desktop over the disk), the disk's bootable cart, or the desktop over a data disk or an empty
 * drive. The cart that boots is the one linked in (CART=gem for the desktop). */
#ifndef ZM_KOS_HOST_H
#define ZM_KOS_HOST_H

#include <stdint.h>

#include "host.h"
#include "sha256.h"

/* scene_hash_kos.mjs's constants (rom/kos/kos.zig). */
#define KOS_BOOT_COLD 0u
#define KOS_BOOT_WARM 1u
#define KOS_DEV_DESKTOP 0u
#define KOS_DEV_DRIVE_A 1u

/* After host_boot_machine(): mount the drive ("none": empty), kosSetBoot, hwInit, kosPostStart.
 * post_frames 0: no POST. -1 (said on stderr) when the disk cannot be read or parsed. */
int host_kos_start(struct w2c_env* e, const char* drive, uint32_t post_frames, int warm);
/* Before each frame: the phase change the last frame asked for, then kosTick. */
void host_kos_between(struct w2c_env* e);
/* 1 once the linked cart runs (host/main.c's frame() then serves the frames). */
int host_kos_in_cart(void);
/* A POST or boot-sector frame, hashed as host/main.c's frame() hashes. */
void host_kos_frame(struct w2c_env* e, sha256_ctx* h, uint32_t planes, uint32_t size);

#endif
