/* The native host's --bootsec X.zmd: host/bootsec_host.c. */
#ifndef ZM_BOOTSEC_HOST_H
#define ZM_BOOTSEC_HOST_H

#include <stdint.h>

#include "host.h"
#include "sha256.h"

/* After host_boot_machine(): hwInit, then the disk's sector instantiated and its boot() run.
 * -1 (said on stderr) when the file cannot be read or its sector does not run. */
int host_bootsec_start(struct w2c_env* e, const char* path);
/* host/main.c's frame() with the sector in the cart's place. */
void host_bootsec_frame(struct w2c_env* e, sha256_ctx* h, uint32_t planes, uint32_t size);

#endif
