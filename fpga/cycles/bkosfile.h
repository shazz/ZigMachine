/* env.kosFileOp on the board (KOS GEMDOS's writes to C:, docs/KOS_GEMDOS.md §7): force-included into the
 * generated env.c and the system's sys_env.c (cycles/board.mk), where tools/host_bridges.py leaves
 * HOST_KOS_FILE_OP calling host_kos_file_hook (null on the board: EDRIVE). ZIGGY cannot see the SD card;
 * glass can: bkosfile.c hands it the cart's request over the window's file block (bkosfreq.h). */
#ifndef ZM_BKOSFILE_H
#define ZM_BKOSFILE_H

#include <stdint.h>

uint32_t board_kos_file_op(uint8_t* mem, uint64_t mem_size, uint32_t req);
#define HOST_KOS_FILE_OP(e, req) board_kos_file_op((e)->memory.data, (e)->memory.size, (req))

#endif
