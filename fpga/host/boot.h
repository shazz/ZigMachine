#ifndef HOST_BOOT_H
#define HOST_BOOT_H

#include "host.h"

/* Instantiate machine, rom and cart into e and boot the cart (scene_hash.mjs boot()):
 * host_boot_machine then host_boot_cart. A disk's boot sector (host/bootsec.h) runs between
 * the two halves, as the browser runs it before it instantiates the cart. */
void host_boot(struct w2c_env* e);
void host_boot_machine(struct w2c_env* e); /* the shared memory, the machine and the ROM */
void host_boot_cart(struct w2c_env* e);    /* the cart over them, hwInit, its boot() and skipBoot() */

/* Invoke a cart export by name with JS-style arguments; -1 if it has none. */
int host_call(struct w2c_env* e, const char* name, const double* args, int n);

#endif
