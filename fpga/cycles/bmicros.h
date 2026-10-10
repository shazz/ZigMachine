/* env.hostMicros on the board: the cart's benchmark clock (decisions.md 2026-10-10,
 * "hostMicros"), in microseconds of the sys clock. Force-included into the generated
 * env.c (cycles/board.mk), where tools/host_gen.py leaves HOST_MICROS() at 0. */
#ifndef ZM_BMICROS_H
#define ZM_BMICROS_H

#include <stdint.h>

uint32_t board_micros(void);
#define HOST_MICROS() board_micros()

#endif
