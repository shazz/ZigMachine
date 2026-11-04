/* env.kosDriveRead on the board (KOS's C:, docs/KOS_FAT.md F5): force-included into the generated
 * env.c and the system's sys_env.c (cycles/board.mk, split.mk), where tools/host_bridges.py
 * leaves HOST_KOS_DRIVE_READ reading host_cdisk's image (empty on the board). ZIGGY cannot see
 * the SD card; glass can: bkosdrive.c asks it over the window's request block (bkosreq.h). */
#ifndef ZM_BKOSDRIVE_H
#define ZM_BKOSDRIVE_H

#include <stdint.h>

uint32_t board_kos_drive_read(uint8_t* mem, uint64_t mem_size, uint32_t unit, uint32_t sector, uint32_t count,
                              uint32_t dst);
#define HOST_KOS_DRIVE_READ(e, unit, sector, count, dst) \
    board_kos_drive_read((e)->memory.data, (e)->memory.size, (unit), (sector), (count), (dst))

#endif
