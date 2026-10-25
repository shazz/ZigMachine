/* ZIGGY's drive: the disk in DDR (bdisk.h). ZWINDOW wrote the disk and its descriptor
 * before letting the CPU out of reset, and nothing here writes either, so the D-cache
 * never holds a stale line of them. U-Boot's flow and a glass older than the disk write
 * no descriptor: then there is no disk, and diskReadBlock answers 0, scene_hash.mjs's stub. */
#include "bdisk.h"

#include <stdio.h>

#include "bmailbox.h"
#include "disk.h"
#include "glass_cart.h"
#include "glass_map.h"

/* picolibc.ld: where the image's load copy ends, i.e. the end of what ZWINDOW placed at 0. */
extern const char __data_source_end[];

#define DISK_DESC_ADDR (CART_CPU_BASE + DDR_CART_BYTES - DISK_DESC_FROM_TOP)

_Static_assert(CART_CPU_BASE + DISK_END == ZM_FB0_ADDR, "the disk must end where the pictures start");
_Static_assert(DISK_DESC_WORDS == 4, "bdisk_parse reads four words");

int bdisk_role;
uint32_t bdisk_image_end;

int bdisk_parse(const uint32_t w[4], uint32_t image_end, uint32_t* at, uint32_t* size) {
    if ((w[0] != DISK_MAGIC && w[0] != DISK_MAGIC_PROGRAM) || w[3] != ~(w[0] ^ w[1] ^ w[2])) return 0;
    if (w[1] < image_end || w[1] > DISK_END || w[2] > DISK_END - w[1]) return 0;
    *at = w[1];
    *size = w[2];
    return w[0] == DISK_MAGIC_PROGRAM ? BDISK_PROGRAM : BDISK_CART;
}

void bdisk_boot(void) {
    const volatile uint32_t* d = (const volatile uint32_t*)(uintptr_t)DISK_DESC_ADDR;
    uint32_t w[4] = {d[0], d[1], d[2], d[3]};
    uint32_t at, size;
    uint32_t end = bdisk_image_end ? bdisk_image_end : (uint32_t)(uintptr_t)__data_source_end - CART_CPU_BASE;
    bdisk_role = bdisk_parse(w, end, &at, &size);
    if (!bdisk_role) {
        printf("ZM DISK none\n");
        return;
    }
    host_disk = (host_disk_t){.data = (const uint8_t*)(uintptr_t)(CART_CPU_BASE + at), .size = size};
    printf("ZM DISK %08lx %lu%s\n", (unsigned long)at, (unsigned long)size,
           bdisk_role == BDISK_PROGRAM ? " program" : "");
}

void bdisk_media(void) {
    host_disk = (host_disk_t){0};
    bdisk_boot();
}

void bdisk_report(void) {
    printf("ZM DISK reads %lu bytes %lu\n", (unsigned long)host_disk.reads, (unsigned long)host_disk.bytes);
}
