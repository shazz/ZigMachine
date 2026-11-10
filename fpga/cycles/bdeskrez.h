/* The desktop's mode across a program load (glass/src/map_cart.zig DESK_REZ, rom/rom_deskmode.zig).
 * A program GEM launched, and the desktop it quits back to, are each a new image whose ROM starts
 * fresh: Getrez said "no desktop ran" and NOTEPAD opened in medium over the desk (Matt, board,
 * 9 Nov). The firmware leaves the ROM's deskReturnMode beside its request (bdiskapp.c); the glass
 * carries it into the next load; the next image's firmware hands it to its ROM at boot (bkos.c,
 * deskSetScreenMode) and zeroes it. A reset is no launch: KOS's boot words say so, and the word
 * is dropped (a warm reset keeps the window, so a stale word would outlive it otherwise).
 * Header-only so tests/tb/deskrez_test.c runs it over a plain buffer. */
#ifndef ZM_BDESKREZ_H
#define ZM_BDESKREZ_H

#include <stdint.h>

#include "glass_cart.h"

#define BDESKREZ_NONE 0xFFu
#define BDESKREZ_LAST 2u /* 0 low, 1 medium, 2 the desk */

/* The word for the ROM's mode (deskReturnMode): 0 when it has none. */
static inline uint32_t bdeskrez_word(uint32_t mode) {
    return mode <= BDESKREZ_LAST ? DESK_REZ_TAG | mode : 0;
}

/* At boot: the carried mode, or BDESKREZ_NONE (no word, a malformed one, or a reset: `reset`
 * is KOS's boot magic present). The word is zeroed either way: one load uses it once. */
static inline uint32_t bdeskrez_take(volatile uint32_t* w, int reset) {
    uint32_t v = *w;
    *w = 0;
    if (reset || (v & DESK_REZ_TAG_MASK) != DESK_REZ_TAG) return BDESKREZ_NONE;
    v &= ~DESK_REZ_TAG_MASK;
    return v <= BDESKREZ_LAST ? v : BDESKREZ_NONE;
}

#endif
