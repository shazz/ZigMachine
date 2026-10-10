/* The board firmware's report to the ARM (bboard.c): the glass's cart state
 * codes (fpga/glass/src/map.zig CART_*, gen/glass_map.py) and the heartbeat. */
#ifndef ZM_BBOARD_H
#define ZM_BBOARD_H

#include <stdint.h>

enum { ZM_CART_RESET = 0, ZM_CART_BOOTING = 1, ZM_CART_RUNNING = 2, ZM_CART_TRAPPED = 3, ZM_CART_ARG_SHIFT = 8 };

void board_state(uint32_t state);
void board_beat(uint32_t frames);

#endif
