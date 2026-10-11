/* The drive's code as the firmware links it (host/disk.h, cycles/bdisk.c), natively, for
 * tests/test_board_disk.py, which runs the browser's diskReadBlock over the same cases.
 *
 *   disk_test drive DISK|-   stdin "block dst" lines -> "n fnv" (n = -1: the JS's RangeError;
 *                            fnv: FNV-1a of the whole 64 KiB memory after the call)
 *   disk_test desc           stdin "w0 w1 w2 w3 image_end" (hex) -> "ok at size" | "none" */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bdisk.h"
#include "disk.h"

#define MEM_BYTES 65536u

host_disk_t host_disk;            /* env.c's, on the board */
const char __data_source_end[1]; /* picolibc.ld's, on the board; bdisk_boot is not called here */

static uint32_t fnv(const uint8_t* p, size_t n) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) h = (h ^ p[i]) * 16777619u;
    return h;
}

static int drive(const char* path) {
    static uint8_t mem[MEM_BYTES];
    for (uint32_t i = 0; i < MEM_BYTES; i++) mem[i] = (uint8_t)(i * 7);
    if (strcmp(path, "-") != 0) {
        FILE* f = fopen(path, "rb");
        static uint8_t buf[1 << 20];
        if (!f) return 2;
        host_disk.size = (uint32_t)fread(buf, 1, sizeof buf, f);
        host_disk.data = buf;
        fclose(f);
    }
    unsigned long block, dst;
    while (scanf("%lx %lx", &block, &dst) == 2) {
        int64_t n = host_disk_read(&host_disk, (uint32_t)block, (uint32_t)dst, mem, MEM_BYTES);
        printf("%lld %08x\n", (long long)n, fnv(mem, MEM_BYTES));
    }
    return 0;
}

static int desc(void) {
    unsigned long v[5];
    while (scanf("%lx %lx %lx %lx %lx", &v[0], &v[1], &v[2], &v[3], &v[4]) == 5) {
        uint32_t w[4] = {(uint32_t)v[0], (uint32_t)v[1], (uint32_t)v[2], (uint32_t)v[3]}, at, size;
        if (bdisk_parse(w, (uint32_t)v[4], &at, &size)) printf("ok %x %x\n", at, size);
        else printf("none\n");
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc == 3 && strcmp(argv[1], "drive") == 0) return drive(argv[2]);
    if (argc == 2 && strcmp(argv[1], "desc") == 0) return desc();
    fprintf(stderr, "usage: disk_test drive DISK|- | desc\n");
    return 2;
}
