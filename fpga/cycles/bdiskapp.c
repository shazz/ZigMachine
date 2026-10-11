/* GEM over a data disk on the board: bdiskapp.h. Compiled per cart (it calls the cart's
 * exports through host_dapp, tools/host_gen.py), as binput.c is. */
#include "bdiskapp.h"

#include <stdio.h>

#include "disk.h"
#include "disk_app.h"

static zmd_dir_t g_dir; /* 15 KB: the parsed FAT, in .bss */
static disk_app_t g_dapp;
static int g_on;

void bdiskapp_boot(void) {
    if (!host_disk.data) return; /* no disk: nothing to tell GEM, as the browser with none */
    int rc = zmd_dir_parse(host_disk.data, host_disk.size, &g_dir);
    if (rc || g_dir.bootable) { /* a bootable disk runs its own cart: the browser's diskApp = false */
        printf("ZM GEMDISK off %d\n", rc);
        return;
    }
    g_dapp = (disk_app_t){.dir = &g_dir};
    g_on = 1;
    printf("ZM GEMDISK data %lu\n", (unsigned long)g_dir.n);
}

void bdiskapp_frame(struct w2c_env* e, long f) {
    if (!g_on || !disk_app_frame(e, &g_dapp)) return;
    uint32_t n = g_dapp.name_len < ZMD_FIND_MAX ? g_dapp.name_len : ZMD_FIND_MAX;
    printf("ZM CARTREQ %ld %lu %.*s %d\n", f, (unsigned long)g_dapp.req, (int)n, (const char*)g_dapp.name,
           g_dapp.file != 0);
}
