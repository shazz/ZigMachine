/* tests/chisel_async: the board's clock and finish, for bchisel.c on the host. */
#include <stdint.h>
#include <stdlib.h>
static inline uint32_t board_cycles(void) { return 0; }
static inline void board_finish(int code) { exit(100 + (code & 0x7F)); }
