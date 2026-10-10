/* glass/firmware/glass_boot.c: which boot the cart CPU makes, and what it keeps. */
#include <stdio.h>

#include "glass_boot.h"

static int failures = 0;
#define CHECK(cond, msg)                         \
    do {                                         \
        if (!(cond)) {                           \
            printf("FAIL %d: %s\n", __LINE__, msg); \
            failures++;                          \
        }                                        \
    } while (0)

#define ARENA (7u << 20)

int main(void) {
    glass_mem_mark_t zeroed = {0, 0}, mark = {0, 0};
    CHECK(glass_boot_kind(0, &zeroed, ARENA) == GLASS_BOOT_COLD, "no WARM: cold");
    CHECK(glass_boot_kind(1, &zeroed, ARENA) == GLASS_BOOT_WARM_LOST, "WARM over zeroed memory: lost");
    glass_boot_mark(&mark, ARENA);
    CHECK(glass_boot_kind(1, &mark, ARENA) == GLASS_BOOT_WARM, "WARM over a marked arena: warm");
    CHECK(glass_boot_kind(0, &mark, ARENA) == GLASS_BOOT_COLD, "a cold boot ignores an old mark");
    CHECK(glass_boot_kind(1, &mark, ARENA + 4) == GLASS_BOOT_WARM_LOST, "a mark for another layout is not trusted");
    CHECK(glass_boot_kind(2, &mark, ARENA) == GLASS_BOOT_COLD, "only bit 0 of the CSR is WARM");

    glass_boot_plan_t cold = glass_boot_plan(GLASS_BOOT_COLD);
    CHECK(cold.zero_arena && cold.data_segments && cold.call_init, "cold: clear, segments, init");
    CHECK(cold.report == (CART_BOOTING | GLASS_FW_VERSION << CART_ARG_SHIFT), "cold reports BOOTING + version");
    glass_boot_plan_t warm = glass_boot_plan(GLASS_BOOT_WARM);
    CHECK(!warm.zero_arena && !warm.data_segments && warm.call_init, "warm: keep memory, run init");
    CHECK(warm.report == cold.report, "warm reports BOOTING + version too");
    glass_boot_plan_t lost = glass_boot_plan(GLASS_BOOT_WARM_LOST);
    CHECK(!lost.zero_arena && !lost.data_segments && !lost.call_init, "lost: runs nothing");
    CHECK(lost.report == (CART_TRAPPED | TRAP_WARM_LOST << CART_ARG_SHIFT), "lost reports the trap");
    CHECK(glass_state_word(CART_RUNNING, 0x010203) == 0x01020302u, "state word layout");
    if (failures) return 1;
    printf("glass_boot: ok\n");
    return 0;
}
