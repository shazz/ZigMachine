/* KOS's power-on in the native host: kos_host.h. Step for step apps/scene_hash_kos.mjs. */
#include "kos_host.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "boot.h"
#include "bootsec.h"
#include "disk.h"
#include "host_io.h"
#include "zmd_dir.h"

typedef enum { PH_POST, PH_SECTOR, PH_CART } phase_t;
typedef enum { GO_NONE, GO_DRIVE, GO_CHAIN } next_t;

static phase_t g_phase;
static next_t g_next;
static int g_sector, g_chain, g_bootable, g_data;
static bootsec_t g_b; /* ~10 KB: the sector's interpreter, as host/bootsec_host.c's */

/* What drive A holds (scene_hash_kos.mjs driveA): an executable sector, its chainloaded cart
 * (none = the desktop over the disk), a bootable disk, a data disk. */
static int classify(const char* path) {
    if (strcmp(path, "none") == 0) return 0;
    host_io_mount_disk(path);
    static zmd_dir_t dir; /* 15 KB */
    if (zmd_dir_parse(host_disk.data, host_disk.size, &dir)) {
        fprintf(stderr, "host: %s: not a disk the browser mounts\n", path);
        return -1;
    }
    g_sector = bootsec_executable(host_disk.data, host_disk.size);
    g_chain = g_sector && dir.bootable; /* zmd_dir: a v2 sector is bootable when it names a cart */
    g_bootable = dir.bootable;
    g_data = !dir.bootable;
    return 0;
}

int host_kos_start(struct w2c_env* e, const char* drive, uint32_t post_frames, int warm) {
    if (classify(drive)) return -1;
    uint32_t dev = g_bootable ? KOS_DEV_DRIVE_A : KOS_DEV_DESKTOP;
    w2c_rom_kosSetBoot(&e->rom, warm ? KOS_BOOT_WARM : KOS_BOOT_COLD, dev, host_disk.data != NULL, w2c_machine_hwRamFree(&e->machine));
    w2c_machine_hwInit(&e->machine);
    post_frames = w2c_rom_kosPostFrames(&e->rom, post_frames); /* none after a warm reset */
    g_phase = PH_POST;
    g_next = post_frames ? GO_NONE : GO_DRIVE;
    if (post_frames) w2c_rom_kosPostStart(&e->rom, post_frames);
    return 0;
}

/* The cart after drive A or the sector: the desktop over a data disk gets GEM's step. */
static void boot_cart(struct w2c_env* e, int data_disk) {
    host_boot_cart(e);
    if (data_disk) host_io_kos_data_disk();
    g_phase = PH_CART;
}

static void boot_drive(struct w2c_env* e) {
    if (!g_sector) return boot_cart(e, host_disk.data && g_data);
    w2c_machine_hwInit(&e->machine); /* the browser: instantiate the sector, hwInit, boot() */
    wint_status st = bootsec_start(&g_b, host_disk.data, e->memory.data, (uint32_t)e->memory.size,
                                   w2c_machine_hwVideoBase(&e->machine), NULL);
    if (st) { /* the browser's frame would throw: no picture to agree on */
        fprintf(stderr, "host: boot sector: %s\n", bootsec_status(st));
        exit(1);
    }
    g_phase = PH_SECTOR;
}

void host_kos_between(struct w2c_env* e) {
    next_t go = g_next;
    g_next = GO_NONE;
    if (go == GO_DRIVE) boot_drive(e);
    else if (go == GO_CHAIN) boot_cart(e, !g_chain);
    w2c_rom_kosTick(&e->rom);
}

int host_kos_in_cart(void) { return g_phase == PH_CART; }

static void hash_off(sha256_ctx* h, uint32_t p) {
    char off[16];
    if (h) sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
}

void host_kos_frame(struct w2c_env* e, sha256_ctx* h, uint32_t planes, uint32_t size) {
    w2c_machine_hwClear(&e->machine);
    if (g_phase == PH_POST) {
        if (w2c_rom_kosPostFrame(&e->rom)) g_next = GO_DRIVE;
    } else {
        int rc = bootsec_frame(&g_b, 16.6f);
        if (rc < 0 && g_b.st) {
            fprintf(stderr, "host: boot sector: %s\n", bootsec_status(g_b.st));
            exit(1);
        }
        if (rc == 1) g_next = GO_CHAIN;
    }
    for (uint32_t p = 0; p < planes; p++) {
        int on = g_phase == PH_POST ? p == 0 : bootsec_plane_on(&g_b, p);
        if (!on) {
            hash_off(h, p);
            continue;
        }
        w2c_machine_hwRenderPlane(&e->machine, p);
        if (h) sha256_update(h, e->memory.data + w2c_machine_hwPhysicalPtr(&e->machine), size);
    }
}
