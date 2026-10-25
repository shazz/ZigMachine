/* GEM over a data disk on the board (bdiskapp.c, host/disk_app.h): the browser boots GEM for a
 * disk that is not bootable and, each frame, tells it the disk is in and hands it the FAT
 * listing once it is booted. The firmware does the same over the disk ZWINDOW placed in DDR
 * (bdisk.h), deciding as the browser does, from the disk's own boot sector.
 * Lines (sim): "ZM GEMDISK data n" (n files) or "ZM GEMDISK off rc" at boot when there is a
 * disk; "ZM CARTREQ f req name found" when the cart asks for a cart swap. */
#ifndef ZM_BDISKAPP_H
#define ZM_BDISKAPP_H

#include "host.h"

void bdiskapp_boot(void);                       /* after bdisk_boot(): it reads only the disk */
/* After bdiskapp_boot: the disk boots its own cart (zmd_dir's bootable; KOS's boot_dev, bkos.h). */
extern int bdiskapp_bootable;
void bdiskapp_frame(struct w2c_env* e, long f); /* after cart.frame() */
/* KOS's media change (glass/src/app_media.zig): once a frame, before cart.frame(). When the glass
 * changed drive A, the drive is read again; the desktop (a cart booted for a data disk or an empty
 * drive) gets insertDisk and, for a data disk, the listing anew; KOS gets kosMediaChange. Line
 * "ZM KOS media f present". */
void bdiskapp_media(struct w2c_env* e, long f);

#endif
