/* Booting the three modules the way apps/scene_hash.mjs boot() does, plus the
 * parts of the env that are not per-cart: the shared memory and --call. */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "boot.h"

/* Every module's `env.memory` import resolves here: one memory, as in the JS
 * `new WebAssembly.Memory({ initial: PAGES, maximum: PAGES })`. */
wasm_rt_memory_t* w2c_env_memory(struct w2c_env* e) { return &e->memory; }

/* The order is scene_hash.mjs's, and it matters: instantiation runs each
 * module's data segments into the shared memory, and hwSetRomHigh lands between
 * the rom and the cart. */
void host_boot(struct w2c_env* e) {
    /* Calloc'd and bounds-checked (WASM_RT_USE_MMAP=0): zeroed like a fresh
     * wasm memory, and no guard pages so it runs on a bare rv32 too. */
    wasm_rt_allocate_memory(&e->memory, host_pages, host_pages, false, WASM_DEFAULT_PAGE_SIZE);
    wasm2c_machine_instantiate(&e->machine, e);
    wasm2c_rom_instantiate(&e->rom, e);
    w2c_machine_hwSetRomHigh(&e->machine, host_rom_high);
    wasm2c_cart_instantiate(&e->cart, e);
    w2c_machine_hwSetCartHigh(&e->machine, host_cart_high);
    w2c_machine_hwInit(&e->machine);
    w2c_cart_boot(&e->cart);
    w2c_cart_skipBoot(&e->cart);
}

/* ECMAScript ToInt32: NaN and infinities give 0, everything else wraps mod 2^32. */
u32 host_to_i32(double x) {
    if (!isfinite(x)) return 0;
    double m = fmod(trunc(x), 4294967296.0);
    if (m < 0) m += 4294967296.0;
    return (u32)m;
}

/* demo[name](...args): missing arguments are `undefined`, which converts like
 * NaN (0 for an i32, NaN for a float); extra ones are ignored. */
int host_call(struct w2c_env* e, const char* name, const double* args, int n) {
    double full[HOST_MAX_ARGS];
    for (int i = 0; i < HOST_MAX_ARGS; i++) full[i] = i < n ? args[i] : NAN;
    for (const host_export* x = host_exports; x->name; x++) {
        if (strcmp(x->name, name) == 0) {
            x->fn(e, full);
            return 0;
        }
    }
    fprintf(stderr, "host: cart has no export %s\n", name);
    return -1;
}
