/* The SID engine natively (libs/c/crsid/zm_sid.c, the C BARD runs), for the parity harness
 * (apps/sid_check.mjs): load tunes in order, render each, print an FNV-1a hash per 2205 samples
 * (0.1 s at 22.05 kHz) and optionally the raw s16 PCM of the last tune.
 *   sid_render <blocks> <tune.sid> <subtune> [<tune.sid> <subtune>]... [-o out.raw]
 * Build: cc -O2 -I<patched tree> -I libs/c/crsid fpga/tools/sid_render.c libs/c/crsid/zm_sid.c
 * (fpga/tests/test_sid_native.py does, on patch.sh's output). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zm_sid.h"

#define BLOCK 2205u

static uint8_t *slurp(const char *path, uint32_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t *d = malloc(0x10000 + 0x7C + 2);
    *len = d ? (uint32_t)fread(d, 1, 0x10000 + 0x7C + 2, f) : 0;
    fclose(f);
    return d;
}

static uint32_t fnv(const int16_t *pcm, uint32_t n) {
    uint32_t h = 2166136261u;
    for (uint32_t i = 0; i < n; i++) h = (h ^ (uint16_t)pcm[i]) * 16777619u;
    return h;
}

int main(int argc, char **argv) {
    const char *out = NULL;
    if (argc >= 3 && strcmp(argv[argc - 2], "-o") == 0) out = argv[argc - 1], argc -= 2;
    if (argc < 4 || argc % 2 != 0) return fprintf(stderr, "usage: %s blocks tune.sid sub [...] [-o out.raw]\n", argv[0]), 2;
    int blocks = atoi(argv[1]);
    static int16_t pcm[BLOCK];
    FILE *raw = NULL;
    for (int t = 2; t < argc; t += 2) {
        uint32_t len = 0;
        uint8_t *file = slurp(argv[t], &len);
        if (!file) return fprintf(stderr, "%s: cannot read %s\n", argv[0], argv[t]), 1;
        uint32_t st = zm_sid_load(file, len, (uint32_t)atoi(argv[t + 1]));
        printf("LOAD %s %u\n", argv[t], (unsigned)st);
        if (t + 2 >= argc && out) raw = fopen(out, "wb");
        for (int b = 0; b < blocks; b++) {
            zm_sid_render(pcm, BLOCK);
            if (raw) fwrite(pcm, 2, BLOCK, raw);
            printf("H %d %08x\n", b, (unsigned)fnv(pcm, BLOCK));
        }
    }
    if (raw) fclose(raw);
    return 0;
}
