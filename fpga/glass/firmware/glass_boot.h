/* The cart CPU's boot, cold or warm (docs/FPGA_GLASS.md, "Cold and warm reset").
 *
 * COLD (the ARM reloaded the image and zeroed the rest of the window): crt0
 * copies .data and zeroes .bss, then main() lays out the machine's memory
 * arena (the wasm linear memory, 7 MiB, at a FIXED address past .bss, not a
 * heap calloc, so a warm boot can find it again), applies the wasm modules'
 * data segments, marks the arena (glass_boot_mark) and calls the cart's init.
 *
 * WARM (CTRL.WARM, read once through the glass_boot_warm CSR; the ARM held the
 * CPU and let it go WITHOUT touching DDR): crt0 still re-initialises the
 * firmware's own C statics (.data from the image's load copy, which the cart
 * never writes; .bss), but the arena is kept as it is: no zeroing, no data
 * segments. The modules' globals (the stack pointer among them) start afresh
 * and the cart's init runs again over its old memory: the ST's reset button.
 *
 * WARM_LOST: a warm boot whose arena carries no mark (a cold load zeroed it,
 * or the last cold boot never got as far as marking it). Nothing is run; the
 * firmware reports CART_TRAPPED with TRAP_WARM_LOST and the ARM offers a cold
 * reset. Never a silent cold boot: the user asked to keep that memory.
 *
 * Plain C, no LiteX: the map's constants come in as -D defines (gen/glass_map.py). */
#ifndef GLASS_BOOT_H
#define GLASS_BOOT_H

#include <stdint.h>

/* This firmware's version, reported in CART_STATE's bits 31:8 (major.minor.patch). */
#define GLASS_FW_MAJOR 0u
#define GLASS_FW_MINOR 1u
#define GLASS_FW_PATCH 0u
#define GLASS_FW_VERSION (GLASS_FW_MAJOR << 16 | GLASS_FW_MINOR << 8 | GLASS_FW_PATCH)

#define GLASS_MEM_MAGIC 0x5A4D4D45u /* "ZMME" */

/* Two words just below the arena: the magic, and a check tied to the arena's
 * size, so a stale mark from a firmware with another layout is not trusted. */
typedef struct {
    uint32_t magic;
    uint32_t check;
} glass_mem_mark_t;

typedef enum { GLASS_BOOT_COLD, GLASS_BOOT_WARM, GLASS_BOOT_WARM_LOST } glass_boot_t;

/* What a boot does, from the steps above. */
typedef struct {
    int zero_arena;    /* clear the machine's memory */
    int data_segments; /* apply the wasm modules' data segments */
    int call_init;     /* run the cart's init export */
    uint32_t report;   /* the first CART_STATE word to write */
} glass_boot_plan_t;

glass_boot_t glass_boot_kind(uint32_t warm_csr, const glass_mem_mark_t* mark, uint32_t arena_bytes);
glass_boot_plan_t glass_boot_plan(glass_boot_t kind);
/* After a cold boot's arena is ready: a later warm boot may keep it. */
void glass_boot_mark(glass_mem_mark_t* mark, uint32_t arena_bytes);
/* A CART_STATE word: the state in bits 7:0, its argument in 31:8. */
uint32_t glass_state_word(uint32_t state, uint32_t arg);

#endif
