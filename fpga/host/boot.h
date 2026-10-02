#ifndef HOST_BOOT_H
#define HOST_BOOT_H

#include "host.h"

/* Instantiate machine, rom and cart into e and boot the cart (scene_hash.mjs boot()). */
void host_boot(struct w2c_env* e);

/* Invoke a cart export by name with JS-style arguments; -1 if it has none. */
int host_call(struct w2c_env* e, const char* name, const double* args, int n);

#endif
