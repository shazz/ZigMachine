/* ZIGGY's drive (bdisk.c): the shelf disk ZWINDOW placed in the cart window, found through
 * its descriptor (fpga/glass/src/map.zig, "the disk in the cart window") and served to the
 * cart as env.diskReadBlock by host/disk.h, exactly as docs/sealed-loader.js serves it.
 * Lines (sim): "ZM DISK offset bytes" or "ZM DISK none" at boot, "ZM DISK reads n bytes b" at the end. */
#ifndef ZM_BDISK_H
#define ZM_BDISK_H

#include <stdint.h>

/* A descriptor's words -> the disk's window offset and bytes, or 0: no magic, a bad check,
 * a disk over the image (which ends at window offset image_end) or past the pictures. */
int bdisk_parse(const uint32_t w[4], uint32_t image_end, uint32_t* at, uint32_t* size);
/* At boot (cold or warm: the descriptor and the disk are ZWINDOW's, never the cart's). */
void bdisk_boot(void);
void bdisk_report(void);

#endif
