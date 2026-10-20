/* fbpeek: the W64 pixel check on the board's Linux (no U-Boot, no md.l).
 * Freezes the cart at a frame boundary through the firmware mailbox (cycles/bmailbox.h, the cart
 * window's top 0x100 bytes), reads the shown picture over /dev/mem, resumes, and prints:
 *   a hash of the picture, nonzero pixels in even and in odd columns, and a few pixels of a row.
 *   fbpeek [MB_PHYS] [ROW] [OUT.bin] [mark]   MB_PHYS default 0x1FFFFF00 (window 0x1E000000 under Linux)
 * "mark": first fill both pictures with 0xDEADBEEF while frozen, run 300 ms, then read: a word the
 * compositor never wrote keeps the marker. Words are counted by their position in a 16-byte pair
 * of 64-bit beats (0 = beat 0 low ... 3 = beat 1 high): marker, zero, and equal to its left pair.
 * Build: zig cc -target arm-linux-musleabihf -mcpu=cortex_a9 -O2 -static -o fbpeek fbpeek.c */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

enum { MAGIC = 0, FB0 = 2, FB1 = 3, PIC_W = 9, PIC_H = 10, CPU_BASE = 11, FREEZE = 13, FROZEN = 14, FRONT = 15 };

static int freeze(volatile uint32_t* mb, int on) {
    mb[FREEZE] = on;
    for (int i = 0; i < 300 && (mb[FROZEN] != 0) != on; i++) usleep(10000);
    return (mb[FROZEN] != 0) == on;
}

static volatile uint32_t* map(int fd, uint32_t phys, uint32_t len) {
    uint32_t base = phys & ~0xFFFu, off = phys - base;
    void* p = mmap(0, len + off, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    if (p == MAP_FAILED) { perror("mmap"); exit(1); }
    return (volatile uint32_t*)((char*)p + off);
}

int main(int argc, char** argv) {
    uint32_t mbp = argc > 1 ? strtoul(argv[1], 0, 0) : 0x1FFFFF00u;
    int row = argc > 2 ? atoi(argv[2]) : 140;
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("/dev/mem"); return 1; }
    volatile uint32_t* mb = map(fd, mbp, 0x100);
    if (mb[MAGIC] != 0x424D4D5Au) { fprintf(stderr, "no mailbox (%08x)\n", mb[MAGIC]); return 1; }
    uint32_t load_base = mbp - 0x01FFFF00u;
    int i, mark = argc > 4;
    if (!freeze(mb, 1)) { fprintf(stderr, "did not freeze\n"); mb[FREEZE] = 0; return 1; }
    uint32_t w = mb[PIC_W], h = mb[PIC_H];
    if (mark) {
        for (int b = 0; b < 2; b++) {
            volatile uint32_t* fb = map(fd, mb[FB0 + b] - mb[CPU_BASE] + load_base, w * h * 4);
            for (i = 0; i < (int)(w * h); i++) fb[i] = 0xDEADBEEFu;
        }
        freeze(mb, 0);
        usleep(300000);
        if (!freeze(mb, 1)) { fprintf(stderr, "did not freeze again\n"); mb[FREEZE] = 0; return 1; }
    }
    uint32_t cpu = mb[FRONT] ? mb[FB1] : mb[FB0];
    volatile uint32_t* pic = map(fd, cpu - mb[CPU_BASE] + load_base, w * h * 4);
    uint32_t* copy = malloc(w * h * 4);
    for (i = 0; i < (int)(w * h); i++) copy[i] = pic[i];
    mb[FREEZE] = 0;
    uint32_t hash = 2166136261u, nz[2] = {0, 0}, same = 0;
    for (i = 0; i < (int)(w * h); i++) {
        hash = (hash ^ copy[i]) * 16777619u;
        if (copy[i]) nz[i & 1]++;
        if ((i & 1) && copy[i] == copy[i - 1]) same++;
    }
    printf("fbpeek %ux%u front=%u hash=%08x nonzero even=%u odd=%u oddsame=%u\n", w, h, mb[FRONT], hash, nz[0], nz[1], same);
    uint32_t mk[4] = {0}, zr[4] = {0};
    for (i = 0; i < (int)(w * h); i++) { mk[i & 3] += copy[i] == 0xDEADBEEFu; zr[i & 3] += copy[i] == 0; }
    printf("by word of a beat pair: marker %u %u %u %u  zero %u %u %u %u\n", mk[0], mk[1], mk[2], mk[3], zr[0], zr[1], zr[2], zr[3]);
    printf("row %d:", row);
    for (i = 0; i < 12; i++) printf(" %08x", copy[row * w + 200 + i]);
    printf("\n");
    if (argc > 3) { FILE* f = fopen(argv[3], "wb"); fwrite(copy, 4, w * h, f); fclose(f); }
    return 0;
}
