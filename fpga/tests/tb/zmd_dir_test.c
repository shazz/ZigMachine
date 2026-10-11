/* GEM's FAT listing as the firmware and the native host build it (host/zmd_dir.h), natively,
 * for tests/test_board_gemdisk.py, which runs the browser's own parseDisk + listing block over
 * the same disks.
 *
 *   zmd_dir_test list DISK ENT MAXF PTR MEM   -> "n HEX" (the n records at PTR in a MEM-byte
 *                                                memory), "err" (the browser throws), or
 *                                                "layout" (ENT under 25), "toomany"
 *   zmd_dir_test find DISK NAMEHEX            -> "1" or "0" (mountedDisk.files[name])
 *   zmd_dir_test boot DISK                    -> "bootable" | "data" | "err" */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zmd_dir.h"

static zmd_dir_t g_dir;
static uint8_t g_disk[1 << 21];

static int load(const char* path, uint32_t* size) {
    FILE* f = fopen(path, "rb");
    if (!f) return -1;
    *size = (uint32_t)fread(g_disk, 1, sizeof g_disk, f);
    fclose(f);
    return zmd_dir_parse(g_disk, *size, &g_dir);
}

static int list(char** a) {
    uint32_t size, ent = (uint32_t)strtoul(a[1], 0, 0), maxf = (uint32_t)strtoul(a[2], 0, 0);
    uint32_t ptr = (uint32_t)strtoul(a[3], 0, 0), mem_size = (uint32_t)strtoul(a[4], 0, 0);
    int rc = load(a[0], &size);
    if (rc) return puts(rc == ZMD_DIR_TOO_MANY ? "toomany" : "err"), 0;
    uint8_t* mem = calloc(mem_size, 1);
    int64_t n = ptr > mem_size ? ZMD_DIR_RANGE : zmd_dir_records(&g_dir, ent, maxf, mem + ptr, mem_size - ptr);
    if (n == ZMD_DIR_LAYOUT) return puts("layout"), 0;
    if (n < 0) return puts("err"), 0;
    printf("%lld ", (long long)n);
    for (uint64_t i = 0; i < (uint64_t)n * ent; i++) printf("%02x", mem[ptr + i]);
    putchar('\n');
    free(mem);
    return 0;
}

static int find(char** a) {
    uint32_t size;
    uint8_t name[300];
    size_t len = strlen(a[1]) / 2;
    if (load(a[0], &size) || len > sizeof name) return puts("err"), 0;
    for (size_t i = 0; i < len; i++) sscanf(a[1] + 2 * i, "%2hhx", &name[i]);
    return puts(zmd_dir_find(&g_dir, name, (uint32_t)len) ? "1" : "0"), 0;
}

int main(int argc, char** argv) {
    uint32_t size;
    if (argc == 7 && strcmp(argv[1], "list") == 0) return list(argv + 2);
    if (argc == 4 && strcmp(argv[1], "find") == 0) return find(argv + 2);
    if (argc == 3 && strcmp(argv[1], "boot") == 0)
        return puts(load(argv[2], &size) ? "err" : g_dir.bootable ? "bootable" : "data"), 0;
    fprintf(stderr, "usage: zmd_dir_test list DISK ENT MAXF PTR MEM | find DISK NAMEHEX | boot DISK\n");
    return 2;
}
