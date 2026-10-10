/* See glass_boot.h. */
#include "glass_boot.h"

static uint32_t mark_check(uint32_t arena_bytes) { return ~GLASS_MEM_MAGIC ^ arena_bytes; }

glass_boot_t glass_boot_kind(uint32_t warm_csr, const glass_mem_mark_t* mark, uint32_t arena_bytes) {
    if (!(warm_csr & 1u)) return GLASS_BOOT_COLD;
    if (mark->magic != GLASS_MEM_MAGIC || mark->check != mark_check(arena_bytes)) return GLASS_BOOT_WARM_LOST;
    return GLASS_BOOT_WARM;
}

uint32_t glass_state_word(uint32_t state, uint32_t arg) {
    return (state & CART_STATE_MASK) | (arg << CART_ARG_SHIFT);
}

glass_boot_plan_t glass_boot_plan(glass_boot_t kind) {
    glass_boot_plan_t p = {0, 0, 0, glass_state_word(CART_BOOTING, GLASS_FW_VERSION)};
    switch (kind) {
    case GLASS_BOOT_COLD:
        p.zero_arena = 1;
        p.data_segments = 1;
        p.call_init = 1;
        break;
    case GLASS_BOOT_WARM:
        p.call_init = 1;
        break;
    case GLASS_BOOT_WARM_LOST:
        p.report = glass_state_word(CART_TRAPPED, TRAP_WARM_LOST);
        break;
    }
    return p;
}

void glass_boot_mark(glass_mem_mark_t* mark, uint32_t arena_bytes) {
    mark->magic = GLASS_MEM_MAGIC;
    mark->check = mark_check(arena_bytes);
}
