/* GEM over a data disk on the board (bdiskapp.c, host/disk_app.h): the browser boots GEM for a
 * disk that is not bootable and, each frame, tells it the disk is in and hands it the FAT
 * listing once it is booted. The firmware does the same over the disk ZWINDOW placed in DDR
 * (bdisk.h), deciding as the browser does, from the disk's own boot sector.
 * Lines (sim): "ZM GEMDISK data n" (n files) or "ZM GEMDISK off rc" at boot when there is a
 * disk; "ZM CARTREQ f req name found" when the cart asks for a cart swap. */
#ifndef ZM_BDISKAPP_H
#define ZM_BDISKAPP_H

#include "host.h"

void bdiskapp_boot(void);                       /* after bdisk_boot() and host_boot() */
void bdiskapp_frame(struct w2c_env* e, long f); /* after cart.frame() */

#endif
