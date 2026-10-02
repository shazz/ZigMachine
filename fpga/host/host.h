/* The native host: machine-video + rom + one cart, each translated by wasm2c
 * (-n machine / -n rom / -n cart), sharing ONE linear memory, driven exactly as
 * apps/scene_hash.mjs drives the wasm modules. See README.md. */
#ifndef HOST_H
#define HOST_H

#include "machine.h"
#include "rom.h"
#include "cart.h"

/* wasm2c's generated code names every import's owner `struct w2c_env`. All three
 * modules import from "env", so this one struct is the whole host: the shared
 * memory plus the instances that serve each other's imports. */
struct w2c_env {
    wasm_rt_memory_t memory;
    w2c_machine machine;
    w2c_rom rom;
    w2c_cart cart;
};

/* Generated per cart by tools/host_gen.py (env.c). */
extern const uint32_t host_pages;      /* SHARED_PAGES from machine/sdk/memmap.zig */
extern const uint32_t host_rom_high;   /* romRam(rom.wasm).high ?? 0, docs/wasm_hiwater.js */
extern const uint32_t host_cart_high;  /* cartRam(cart.wasm).high ?? 0 */

/* A cart export callable from --call. Arguments arrive as JS Numbers (double)
 * and are converted the way the JS-to-wasm boundary converts them. */
typedef struct {
    const char* name;
    void (*fn)(struct w2c_env* e, const double* args);
} host_export;

extern const host_export host_exports[]; /* NULL-terminated */

#define HOST_MAX_ARGS 16

/* ToInt32: what wasm receives for an i32 parameter given a JS Number. */
u32 host_to_i32(double x);

#endif
