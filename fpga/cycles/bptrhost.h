/* env.hostPointerBox on the board (tools/host_bridges.py POINTER_BOX, system table 1.21): the cart
 * says where its picture is (the SDL layer, kestrel_sdl2/src/kestrel_ptrbox.c), and the pointer's
 * box words follow it (bdesk.c, bptrbox.h). Force-included (cycles/board.mk MICROS_board) into the
 * generated env.c / sys_env.c, where the hook expands; anywhere else the hook is a no-op. */
#ifndef ZM_BPTRHOST_H
#define ZM_BPTRHOST_H

#include <stdint.h>

void bdesk_pointer_box(uint32_t x0, uint32_t y0, uint32_t x1, uint32_t y1);
#define HOST_POINTER_BOX(e, x0, y0, x1, y1) ((void)(e), bdesk_pointer_box((x0), (y0), (x1), (y1)))

#endif
