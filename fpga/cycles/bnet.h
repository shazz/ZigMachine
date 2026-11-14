/* env.netOp on the board (ZIGNIC, docs/GEM_NET.md N2): force-included into the generated env.c and the system's
 * sys_env.c (cycles/board.mk), where tools/host_bridges.py leaves HOST_NET_OP answering no_card. ZIGGY has no
 * network; glass has Linux's: bnet.c hands it the cart's Req over the window's NET block (bnetreq.h). */
#ifndef ZM_BNET_H
#define ZM_BNET_H

#include <stdint.h>

uint32_t board_net_op(uint8_t* mem, uint64_t mem_size, uint32_t req);
#define HOST_NET_OP(e, req) board_net_op((e)->memory.data, (e)->memory.size, (req))

#endif
