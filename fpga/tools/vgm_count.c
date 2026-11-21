/* The VGM engine's work, frame by frame (libs/c/vgm/README.md "BARD load"): how many operators it computed
 * (past the 832 shortcut) and how many live channels it rendered in each 1/60 s, so a short BARD bench window
 * can be set against a whole tune's mean and worst frame. Native, no timing: the counts are what BARD runs.
 *   vgm_count <tune.vgm> <seconds> [from to]     prints the per-frame mean and max, and the window's
 * Build: cc -O2 -DZM_YM_COUNT fpga/tools/vgm_count.c, the libs/c/vgm, libs/c/ym2612 and libs/c/sn76489 C files */
#include <stdio.h>
#include <stdlib.h>

#include "../../libs/c/vgm/zm_vgm.h"

extern uint32_t ym_count_ops, ym_count_ch;

#define CAP (8u << 20)

int main(int argc, char **argv) {
    if (argc < 3) return fprintf(stderr, "vgm_count <tune.vgm> <seconds> [from to]\n"), 2;
    FILE *in = fopen(argv[1], "rb");
    if (!in) return perror(argv[1]), 1;
    uint8_t *d = malloc(CAP);
    uint32_t len = d ? (uint32_t)fread(d, 1, CAP, in) : 0;
    fclose(in);
    if (zm_vgm_load(d, len, CAP)) return printf("LOAD refused\n"), 1;
    uint32_t rate = zm_vgm_rate(), frames = (uint32_t)(atof(argv[2]) * 60);
    uint32_t from = argc > 4 ? (uint32_t)(atof(argv[3]) * 60) : 0, to = argc > 4 ? (uint32_t)(atof(argv[4]) * 60) : 0;
    static int16_t lr[2 * 2048];
    double sum = 0, wsum = 0;
    uint32_t max = 0, wmax = 0, wn = 0;
    for (uint32_t f = 0, acc = 0; f < frames; f++) {
        uint32_t n = rate / 60u;
        acc += rate - n * 60u;
        if (acc >= 60u) acc -= 60u, n++;
        ym_count_ops = ym_count_ch = 0;
        zm_vgm_render(lr, n);
        sum += ym_count_ops;
        if (ym_count_ops > max) max = ym_count_ops;
        if (f >= from && f < to) wsum += ym_count_ops, wn++, wmax = ym_count_ops > wmax ? ym_count_ops : wmax;
    }
    printf("ops a frame: mean %.0f max %u (of %u: 24 operators x %u samples)\n", sum / frames, max, 24 * (rate / 60), rate / 60);
    if (wn) printf("window %.1f-%.1f s: mean %.0f max %u\n", from / 60.0, to / 60.0, wsum / wn, wmax);
    return 0;
}
