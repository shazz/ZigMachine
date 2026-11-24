/* The VGM engine natively (libs/c/vgm/zm_vgm.c, the C BARD runs), for the parity harness
 * (apps/harness/vgm_check.mjs) and the local Gens comparison (libs/c/vgm/gens_compare.sh): load a .vgm / .vgz,
 * render `seconds` at the engine's rate, print an FNV-1a hash per 0.1 s block and optionally the PCM.
 *   vgm_render <tune.vgm> <seconds> [-o out.wav]      (a 16-bit stereo WAV at the engine's rate)
 *   vgm_render <tune.vgm> <seconds> -p                the player's output stage instead (zm_vgm_render_paula):
 *                                                     4410 frames at 44.1 kHz a block, its four byte streams hashed
 *   vgm_render <tune.vgm|-> <seconds> -s <script> <block> <feed>
 *                                                     the SFX device (zm_vgm_sfx.c) on before the tune loads, the
 *                                                     script's lines "stamp addr value" pushed `feed` output frames
 *                                                     before their stamp, the output stage run in calls of `block`
 *                                                     frames: hashed as -p, then the device's counters ("-" no tune)
 * Build: cc -O2 fpga/tools/vgm_render.c, libs/c/vgm/{zm_vgm,vgm_seq,vgm_stream,zm_inflate,zm_vgm_out,zm_vgm_sfx,zm_vgm_own}.c,
 *        libs/c/ym2612/{ym2612,ym2612_eg,ym2612_render}.c, libs/c/sn76489/sn76489.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../libs/c/vgm/zm_vgm.h"

#define CAP (8u << 20)

static uint32_t fnv(const int16_t *pcm, uint32_t n, uint32_t h) {
    for (uint32_t i = 0; i < n; i++) h = (h ^ (uint16_t)pcm[i]) * 16777619u;
    return h;
}

static void wav_header(FILE *f, uint32_t rate, uint32_t frames) {
    uint32_t bytes = frames * 4u, v = 36 + bytes, fmt[4] = {16, 1 | 2u << 16, rate, rate * 4};
    uint16_t tail[2] = {4, 16};
    fwrite("RIFF", 1, 4, f), fwrite(&v, 4, 1, f), fwrite("WAVEfmt ", 1, 8, f);
    fwrite(fmt, 4, 4, f), fwrite(tail, 2, 2, f), fwrite("data", 1, 4, f), fwrite(&bytes, 4, 1, f);
}

/* -p: the four Paula byte streams of each 0.1 s at 44.1 kHz, hashed in channel order (hi L, hi R, lo L, lo R). */
static void paula(uint32_t seconds10) {
    static int8_t ch[4][4410];
    for (uint32_t b = 0; b < seconds10; b++) {
        zm_vgm_render_paula(ch[0], ch[1], ch[2], ch[3], 4410);
        uint32_t h = 2166136261u;
        for (int c = 0; c < 4; c++)
            for (int i = 0; i < 4410; i++) h = (h ^ (uint8_t)ch[c][i]) * 16777619u;
        printf("P %u %08x\n", b, h);
    }
}

/* -s: the SFX script over the tune, the pushes `feed` frames early, the stage in `block`-frame calls. */
static int sfx(const char *script, uint32_t seconds10, uint32_t block, uint32_t feed) {
    FILE *f = fopen(script, "r");
    if (!f) return perror(script), 1;
    static uint32_t w[65536][3];
    uint32_t n = 0, at = 0, total = seconds10 * 4410u;
    while (n < 65536 && fscanf(f, "%u %u %u", &w[n][0], &w[n][1], &w[n][2]) == 3) n++;
    fclose(f);
    int8_t *ch[4];
    for (int c = 0; c < 4; c++) ch[c] = calloc(total + block, 1);
    for (uint32_t done = 0; done < total;) {
        while (at < n && w[at][0] < done + block + feed && zm_vgm_sfx_push(w[at][0], w[at][1], w[at][2])) at++;
        uint32_t k = total - done < block ? total - done : block;
        zm_vgm_render_paula(ch[0] + done, ch[1] + done, ch[2] + done, ch[3] + done, k);
        done += k;
    }
    for (uint32_t b = 0; b < seconds10; b++) {
        uint32_t h = 2166136261u;
        for (int c = 0; c < 4; c++)
            for (uint32_t i = 0; i < 4410; i++) h = (h ^ (uint8_t)ch[c][b * 4410u + i]) * 16777619u;
        printf("P %u %08x\n", b, h);
    }
    printf("SFX applied %u refused %u late %u pending %u pushed %u\n", zm_vgm_sfx_stat(ZM_SFX_ST_APPLIED),
           zm_vgm_sfx_stat(ZM_SFX_ST_REFUSED), zm_vgm_sfx_stat(ZM_SFX_ST_LATE), zm_vgm_sfx_stat(ZM_SFX_ST_PENDING), at);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) return fprintf(stderr, "vgm_render <tune.vgm> <seconds> [-o out.wav]\n"), 2;
    if (argc > 6 && !strcmp(argv[3], "-s")) {
        zm_vgm_sfx_on(1);
        if (strcmp(argv[1], "-")) {
            FILE *t = fopen(argv[1], "rb");
            uint8_t *d = t ? malloc(CAP) : NULL;
            if (!d) return perror(argv[1]), 1;
            uint32_t rc = zm_vgm_load(d, (uint32_t)fread(d, 1, CAP, t), CAP);
            fclose(t);
            if (rc) return printf("LOAD %u\n", rc), 1;
        }
        return sfx(argv[4], (uint32_t)(atof(argv[2]) * 10), (uint32_t)atoi(argv[5]), (uint32_t)atoi(argv[6]));
    }
    FILE *in = fopen(argv[1], "rb");
    if (!in) return perror(argv[1]), 1;
    uint8_t *d = malloc(CAP);
    uint32_t len = d ? (uint32_t)fread(d, 1, CAP, in) : 0;
    fclose(in);
    uint32_t rc = zm_vgm_load(d, len, CAP);
    if (rc) return printf("LOAD %u\n", rc), 1;
    if (argc > 3 && !strcmp(argv[3], "-p")) return paula((uint32_t)(atof(argv[2]) * 10)), 0;
    uint32_t rate = zm_vgm_rate(), frames = (uint32_t)(atof(argv[2]) * rate), block = rate / 10;
    FILE *out = argc > 4 && !strcmp(argv[3], "-o") ? fopen(argv[4], "wb") : NULL;
    if (out) wav_header(out, rate, frames);
    int16_t *pcm = malloc(4u * block);
    printf("RATE %u\n", rate);
    for (uint32_t done = 0, b = 0; done < frames; b++) {
        uint32_t k = frames - done < block ? frames - done : block;
        zm_vgm_render(pcm, k);
        if (out) fwrite(pcm, 4, k, out);
        printf("H %u %08x\n", b, fnv(pcm, 2 * k, 2166136261u));
        done += k;
    }
    printf("LOOPS %u\n", zm_vgm_loops());
    if (out) fclose(out);
    return 0;
}
