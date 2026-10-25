/* GEM over a data disk on the board: bdiskapp.h. Compiled per cart (it calls the cart's
 * exports through host_dapp, tools/host_gen.py), as binput.c is. */
#include "bdiskapp.h"

#include <stdio.h>

#include "bboard.h"
#include "bcartreq.h"
#include "bdinval.h"
#include "bdisk.h"
#include "disk.h"
#include "disk_app.h"
#include "glass_cart.h"
#include "glass_map.h"

/* The request block (glass/src/map_cart.zig), between the descriptor and the diagnostic's control. */
#define REQ_ADDR (CART_CPU_BASE + DDR_CART_BYTES - CART_REQ_FROM_TOP)
#define MEDIA_ADDR (CART_CPU_BASE + DDR_CART_BYTES - KOS_MEDIA_FROM_TOP)
_Static_assert(CART_REQ_FROM_TOP < DISK_DESC_FROM_TOP - DISK_DESC_WORDS * 4, "the block is over the descriptor");
_Static_assert(CART_REQ_FROM_TOP - CART_REQ_HEAD_WORDS * 4 - CART_REQ_NAME_MAX >= 0x200, "the block is over bdiag");
_Static_assert(CART_REQ_NAME_MAX >= ZMD_DIR_KEY, "a FAT name must fit the block");

static zmd_dir_t g_dir; /* 15 KB: the parsed FAT, in .bss */
static disk_app_t g_dapp;
static int g_on;
static int g_asked; /* a bootable cart's swap was signalled: no more polls (the browser's `swapping`) */
int bdiskapp_bootable;
static int g_desktop;    /* the cart was booted as KOS's desktop: no disk, or a data disk */
static uint32_t g_media; /* the media word as last seen (map_cart.zig KOS_MEDIA_*) */

/* The disk's state: g_on (GEM over a data disk) from what the drive holds now. */
static void parse(void) {
    g_on = 0;
    bdiskapp_bootable = 0;
    if (!host_disk.data) return; /* no disk: nothing to tell GEM, as the browser with none */
    int rc = zmd_dir_parse(host_disk.data, host_disk.size, &g_dir);
    bdiskapp_bootable = !rc && g_dir.bootable;
    if (rc || g_dir.bootable) { /* a bootable disk runs its own cart: the browser's diskApp = false */
        printf("ZM GEMDISK off %d\n", rc);
        return;
    }
    /* A program GEM launched off the disk: the browser handed GEM the listing, not it. */
    g_dapp = (disk_app_t){.dir = &g_dir, .dir_set = bdisk_role == BDISK_PROGRAM};
    g_on = 1;
    printf("ZM GEMDISK data %lu%s\n", (unsigned long)g_dir.n, g_dapp.dir_set ? " program" : "");
}

void bdiskapp_boot(void) {
    g_asked = 0;
    g_media = *(volatile uint32_t*)(uintptr_t)MEDIA_ADDR;
    parse();
    g_desktop = !bdiskapp_bootable && bdisk_role != BDISK_PROGRAM;
}

void bdiskapp_media(struct w2c_env* e, long f) {
    bdi_inval_line(MEDIA_ADDR); /* the glass wrote it through HP0, past this D$ line */
    uint32_t m = *(volatile uint32_t*)(uintptr_t)MEDIA_ADDR;
    if (m == g_media) return;
    g_media = m;
    zm_dflush(); /* the disk and its descriptor too */
    bdisk_media();
    parse();
    uint32_t present = host_disk.data != 0;
    if (!g_desktop) g_on = 0; /* a cart booted for its own disk: the drive reads the new one, nothing more */
    if (g_desktop && host_dapp.insert_disk) host_dapp.insert_disk(HOST_CART(e), g_on);
    w2c_rom_kosMediaChange(&e->rom, present);
    printf("ZM KOS media %ld %lu\n", f, (unsigned long)present);
}

/* The swap is ZWINDOW's (glass/src/app_request.zig): the block, then CART_STATE. The cart
 * keeps running until the glass holds it for the next load. The D-cache is write-through, so
 * the block is on its way to DDR before the CSR write; the glass takes it once its check holds. */
static void bdiskapp_signal(uint32_t req, const uint8_t* name, uint32_t len) {
    volatile uint32_t* w = (volatile uint32_t*)(uintptr_t)REQ_ADDR;
    bcartreq_write(w, req, name, len);
    printf("ZM REQBLOCK %08lx %lu %lu %08lx\n", (unsigned long)w[0], (unsigned long)w[1], (unsigned long)w[2],
           (unsigned long)w[3]);
    board_state(CART_REQUEST | req << ZM_CART_ARG_SHIFT);
}

/* A bootable cart's pollCartRequest (the browser polls every cart): 1 = boot the shelf disk
 * demo-<tag>.zmd (getCartTagPtr/Len), -1 = back to the cart that loaded this one. */
static void bdiskapp_cart(struct w2c_env* e, long f) {
    if (g_asked || !host_dapp.poll) return;
    uint32_t req = host_dapp.poll(HOST_CART(e));
    if (req == 1 && host_dapp.tag_ptr && host_dapp.tag_len) {
        uint32_t len = host_dapp.tag_len(HOST_CART(e));
        const uint8_t* tag = disk_app_mem(e, host_dapp.tag_ptr(HOST_CART(e)), len);
        printf("ZM CARTREQ %ld 1 %.*s 1\n", f, (int)(len < CART_REQ_NAME_MAX ? len : CART_REQ_NAME_MAX), (const char*)tag);
        bdiskapp_signal(REQ_LOAD_CART, tag, len);
        g_asked = 1;
    } else if (req == 0xFFFFFFFFu) {
        printf("ZM CARTREQ %ld -1 - 1\n", f);
        bdiskapp_signal(REQ_BACK, 0, 0);
        g_asked = 1;
    }
}

void bdiskapp_frame(struct w2c_env* e, long f) {
    if (!g_on) {
        bdiskapp_cart(e, f);
        return;
    }
    if (!disk_app_frame(e, &g_dapp)) return;
    uint32_t n = g_dapp.name_len < ZMD_FIND_MAX ? g_dapp.name_len : ZMD_FIND_MAX;
    printf("ZM CARTREQ %ld %lu %.*s %d\n", f, (unsigned long)g_dapp.req, (int)n, (const char*)g_dapp.name,
           g_dapp.file != 0);
    if (g_dapp.req == REQ_RUN_PROGRAM && g_dapp.file)
        bdiskapp_signal(REQ_RUN_PROGRAM, g_dapp.file->key, g_dapp.file->key_len);
    else if (g_dapp.req == REQ_BACK_TO_OS)
        bdiskapp_signal(REQ_BACK_TO_OS, 0, 0);
}
