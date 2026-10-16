/* ZIGGY's drive (bdisk.c): the shelf disk ZWINDOW placed in the cart window, found through
 * its descriptor (fpga/glass/src/map.zig, "the disk in the cart window") and served to the
 * cart as env.diskReadBlock by host/disk.h, exactly as docs/sealed-loader.js serves it.
 * Lines (sim): "ZM DISK offset bytes [program]" or "ZM DISK none" at boot, "ZM DISK reads n bytes b"
 * at the end. */
#ifndef ZM_BDISK_H
#define ZM_BDISK_H

#include <stdint.h>

/* What the descriptor's magic says the cart is to its disk (glass/src/map_cart.zig): booted for
 * it (DISK_MAGIC), or a program GEM launched off it (DISK_MAGIC_PROGRAM). */
enum { BDISK_NONE = 0, BDISK_CART = 1, BDISK_PROGRAM = 2 };
extern int bdisk_role; /* bdisk_boot's answer */

/* A descriptor's words -> the disk's window offset and bytes, and its BDISK_* role; BDISK_NONE:
 * no magic, a bad check, a disk over the image (which ends at window offset image_end) or
 * past the pictures. */
int bdisk_parse(const uint32_t w[4], uint32_t image_end, uint32_t* at, uint32_t* size);
/* Where the image the disk must follow ends (window offset): 0, the image's own load copy
 * (the monolithic image); the split system sets the lean cart's .bss end (cycles/bsys.c). */
extern uint32_t bdisk_image_end;
/* At boot (cold or warm: the descriptor and the disk are ZWINDOW's, never the cart's). */
void bdisk_boot(void);
void bdisk_report(void);

#endif
