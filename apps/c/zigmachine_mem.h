// ---------------------------------------------------------------------------
// zigmachine_mem.h — the machine's RAM arena (HW 1.7.0) for a C cart.
//
// malloc for a cart: zeroed memory above the cart's static data + stack, below
// the video region. Prefer it to a big `static` buffer: with --import-memory the
// linker cannot assume memory is zero, so a zero-filled static can be written
// out byte for byte into the cart binary and count against the 2 MiB window
// before the cart runs (apps/zero_segments.mjs fails the build on one of 64 KB+).
//
//     #include "../zigmachine_mem.h"
//     static u16 *work;                                   // in boot():
//     work = zm_alloc_array(u16, 320 * 200);              // zeroed; NULL when full
//     if (!work) { ... }                                  // zm_alloc_failures() counts it
//
//     zm_mark m = zm_mark_now();  ...  zm_release(m);     // one region per demo part
//
// Nothing is freed singly. A new cart (boot, swap) starts with an empty arena.
// See docs/MEMORY.md and machine/sdk/hardware.zig.
// ---------------------------------------------------------------------------
#ifndef ZIGMACHINE_MEM_H
#define ZIGMACHINE_MEM_H

#define ZM_MEM_IMPORT(name) __attribute__((import_module("env"), import_name(name)))
ZM_MEM_IMPORT("hwRamAlloc") extern unsigned hwRamAlloc(unsigned bytes, unsigned alignment);
ZM_MEM_IMPORT("hwRamMark") extern unsigned hwRamMark(void);
ZM_MEM_IMPORT("hwRamRelease") extern void hwRamRelease(unsigned mark);
ZM_MEM_IMPORT("hwRamAllocFailures") extern unsigned hwRamAllocFailures(void);
ZM_MEM_IMPORT("hwRamFree") extern unsigned hwRamFree(void);

typedef unsigned zm_mark;

// `bytes` zeroed bytes aligned to `alignment` (a power of two, 1..65536), or NULL.
static inline void *zm_alloc(unsigned bytes, unsigned alignment) {
    return (void *)(unsigned long)hwRamAlloc(bytes, alignment);
}
// n zeroed Ts aligned for T, or NULL (n * sizeof(T) past 4 GB is refused too).
#define zm_alloc_array(T, n) \
    ((T *)((unsigned long long)(n) * sizeof(T) > 0xFFFFFFFFull \
        ? zm_alloc(0xFFFFFFFFu, 1) : zm_alloc((unsigned)((n) * sizeof(T)), _Alignof(T))))

static inline zm_mark zm_mark_now(void) { return hwRamMark(); }
static inline void zm_release(zm_mark m) { hwRamRelease(m); }
static inline unsigned zm_alloc_failures(void) { return hwRamAllocFailures(); }
static inline unsigned zm_ram_free(void) { return hwRamFree(); }

#endif
