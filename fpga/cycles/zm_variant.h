/* Spliced into each wasm2c output (machine.c, rom.c, cart.c) by the cycles
 * Makefile, after wasm2c's memory-check macros are defined and before they are
 * used. It changes HOW wasm memory is accessed, never what is computed, and the
 * hashes prove that for every build.
 *
 *   (neither)        stock wasm2c: every access bounds-checked, read by memcpy
 *   ZM_NO_BOUNDS     no per-access check. On the board the bus window seals the
 *                    cart instead, so this is the honest figure.
 *   ZM_ALIGNED       + accesses as native loads/stores (below).
 *
 * Why ZM_ALIGNED exists: wasm2c reads memory with memcpy because a wasm address
 * may be misaligned. GCC cannot know it is not, and rv32 traps on a misaligned
 * lw, so it expands every 4-byte access to 4 lbu + 4 sb + 1 lw. Real carts
 * almost always access naturally aligned addresses, so ZM_ALIGNED lets the
 * compiler emit one lw/sw and leaves the rare misaligned access to the trap
 * handler (trap.c), which emulates and counts it. */
#ifndef ZM_VARIANT_H
#define ZM_VARIANT_H

#if defined(ZM_ALIGNED) && !defined(ZM_NO_BOUNDS)
#error "ZM_ALIGNED is only measured together with ZM_NO_BOUNDS"
#endif

#ifdef ZM_NO_BOUNDS
#undef MEMCHECK_DEFAULT32
#define MEMCHECK_DEFAULT32(mem, local_memory_size, a, t)
#undef MEMCHECK_GENERAL
#define MEMCHECK_GENERAL(mem, a, t)
#endif

#ifdef ZM_ALIGNED
#include <stdint.h>
#include <string.h>

/* The fixed sizes are the wasm loads and stores (and register reinterprets);
 * anything else (data segments, memory.copy) stays a real memcpy. An 8-byte
 * access on rv32 is two lw/sw, so it needs 4-byte alignment, not 8. */
static inline void* zm_memcpy(void* d, const void* s, size_t n) {
    switch (n) {
        case 1: *(uint8_t*)d = *(const uint8_t*)s; return d;
        case 2: *(uint16_t*)d = *(const uint16_t*)s; return d;
        case 4: *(uint32_t*)d = *(const uint32_t*)s; return d;
        case 8:
            ((uint32_t*)d)[0] = ((const uint32_t*)s)[0];
            ((uint32_t*)d)[1] = ((const uint32_t*)s)[1];
            return d;
        default: return memcpy(d, s, n);
    }
}
#undef wasm_rt_memcpy
#define wasm_rt_memcpy zm_memcpy
#endif

#endif
