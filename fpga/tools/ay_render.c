/* The AY engine natively (libs/c/ayumi zm_ay_bank.c, the C BARD runs), for the parity harness
 * (apps/ay_live_check.mjs): a script of writes {t, a, v} (u32 little-endian, t ascending: the output sample a
 * write lands before), rendered `n` stereo frames; an FNV-1a hash of each 4410-frame block (0.1 s), and
 * optionally the raw s16 stereo.
 *   ay_render <script.bin> <frames> [-o out.raw]
 * Build: cc -O2 -I libs/c/ayumi fpga/tools/ay_render.c libs/c/ayumi/zm_ay.c libs/c/ayumi/zm_ay_cfg.c libs/c/ayumi/zm_ay_bank.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zm_ay_bank.h"

#define BLOCK 4410u

static uint32_t fnv(const int16_t *pcm, uint32_t n, uint32_t h) {
    for (uint32_t i = 0; i < n; i++) h = (h ^ (uint16_t)pcm[i]) * 16777619u;
    return h;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "ay_render <script.bin> <frames> [-o out.raw]\n"); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    static uint32_t w[3 * 65536];
    uint32_t nw = (uint32_t)fread(w, 12, 65536, f), at = 0;
    fclose(f);
    uint32_t frames = (uint32_t)strtoul(argv[2], NULL, 10);
    FILE *raw = argc > 4 && !strcmp(argv[3], "-o") ? fopen(argv[4], "wb") : NULL;
    static int16_t pcm[2 * BLOCK];
    zm_ay_bank_reset();
    for (uint32_t b = 0, t = 0; t < frames; b++) {
        uint32_t end = t + BLOCK < frames ? t + BLOCK : frames, h = 2166136261u, k = 0;
        while (t < end) {
            while (at < nw && w[3 * at] <= t) { zm_ay_bank_write(w[3 * at + 1], w[3 * at + 2]); at++; }
            uint32_t next = at < nw && w[3 * at] < end ? w[3 * at] : end;
            zm_ay_bank_render(pcm + 2 * k, next - t);
            k += next - t;
            t = next;
        }
        h = fnv(pcm, 2 * k, h);
        if (raw) fwrite(pcm, 4, k, raw);
        printf("H %u %08x\n", b, h);
    }
    if (raw) fclose(raw);
    return 0;
}
