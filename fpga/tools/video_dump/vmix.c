/* vmix: the picture a browser shows for a recorded frame, computed from the
 * frame's PFBs exactly as docs/sealed-loader.js and Chrome build it. It is the
 * oracle of the RTL plane mixer (rtl/video/zm_video_mix.v).
 *
 *   vmix frame <dir> <frame> [--layers] -> <dir>/f<frame>.mix     (800x280 RGB)
 *                                          <dir>/f<frame>.layers  (the 4 canvases, RGBA, if asked)
 *   vmix layers <layers.rgba> <mask> <out.rgb>   compose arbitrary canvases
 *
 * What the loader does: canvas i (stacked in DOM order, 0 at the bottom) gets
 * the PFB as it is after hwRenderPlane(i), for each enabled plane i; when no
 * plane is enabled, canvas 0 gets the PFB after hwClear. Canvases of disabled
 * planes are blank. The tube behind them is #121010 (docs/css/crt.css).
 *
 * What Chrome does (measured by tools/mix_chrome.mjs, exact on every one of
 * 65,536 colour x alpha pairs and on random 4-canvas stacks): putImageData
 * premultiplies, P = round(c * a / 255); each canvas is then drawn source-over,
 * D = P + (D * (256 - a) >> 8). That is Skia's software path; a GPU compositor
 * rounds differently (up to 4 levels on partial alpha). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zm_memmap.h"

#define W ZM_RASTER_WIDTH
#define H ZM_RASTER_HEIGHT
#define PX (W * H)
#define CANVASES ZM_NB_PLANES

static const uint8_t k_tube[3] = {0x12, 0x10, 0x10};

static unsigned div255(unsigned x) { return (x + 128 + ((x + 128) >> 8)) >> 8; }

/* Every canvas in `mask`, bottom first, over the tube: RGBA in, RGB out. */
static int compose(const uint8_t* canvases, unsigned mask, uint8_t* out) {
    for (int i = 0; i < PX; i++) {
        unsigned d[3] = {k_tube[0], k_tube[1], k_tube[2]};
        for (int k = 0; k < CANVASES; k++) {
            if (!((mask >> k) & 1)) continue;
            const uint8_t* s = canvases + ((size_t)k * PX + (size_t)i) * 4;
            for (int c = 0; c < 3; c++) d[c] = div255(s[c] * s[3]) + ((d[c] * (256u - s[3])) >> 8);
        }
        for (int c = 0; c < 3; c++) {
            if (d[c] > 255) return -1; /* cannot happen; a model error if it does */
            out[(size_t)i * 3 + c] = (uint8_t)d[c];
        }
    }
    return 0;
}

static uint8_t* slurp(const char* path, size_t want) {
    FILE* f = fopen(path, "rb");
    uint8_t* b = malloc(want + 1);
    size_t got = f ? fread(b, 1, want + 1, f) : 0;
    if (f) fclose(f);
    if (got != want) {
        fprintf(stderr, "vmix: %s: want %zu bytes, got %zu\n", path, want, got);
        exit(1);
    }
    return b;
}

static void spit(const char* path, const uint8_t* b, size_t n) {
    FILE* f = fopen(path, "wb");
    if (!f || fwrite(b, 1, n, f) != n) {
        fprintf(stderr, "vmix: cannot write %s\n", path);
        exit(1);
    }
    fclose(f);
}

/* The canvases the loader fills for one recorded frame, and which are drawn. */
static unsigned frame_canvases(const char* dir, const char* frame, uint8_t* canvases) {
    char path[1024];
    unsigned planes = 0;
    int vram = 0;
    snprintf(path, sizeof path, "%s/f%s.meta", dir, frame);
    FILE* m = fopen(path, "r");
    if (!m || fscanf(m, "planes %u vram_changed %d", &planes, &vram) != 2) {
        fprintf(stderr, "vmix: cannot read %s\n", path);
        exit(1);
    }
    fclose(m);
    int n = 1 + __builtin_popcount(planes);
    snprintf(path, sizeof path, "%s/f%s.pfb", dir, frame);
    uint8_t* pfb = slurp(path, (size_t)n * PX * 4);
    memset(canvases, 0, (size_t)CANVASES * PX * 4);
    if (!planes) memcpy(canvases, pfb, (size_t)PX * 4); /* no plane: the cleared PFB */
    for (int p = 0, at = 1; p < CANVASES; p++)
        if ((planes >> p) & 1) memcpy(canvases + (size_t)p * PX * 4, pfb + (size_t)at++ * PX * 4, (size_t)PX * 4);
    free(pfb);
    return planes ? planes : 1u;
}

int main(int argc, char** argv) {
    static uint8_t canvases[(size_t)CANVASES * PX * 4], out[(size_t)PX * 3];
    char path[1024];
    unsigned mask;
    if ((argc == 4 || (argc == 5 && !strcmp(argv[4], "--layers"))) && !strcmp(argv[1], "frame")) {
        mask = frame_canvases(argv[2], argv[3], canvases);
        snprintf(path, sizeof path, "%s/f%s.layers", argv[2], argv[3]);
        if (argc == 5) spit(path, canvases, sizeof canvases);
        snprintf(path, sizeof path, "%s/f%s.mix", argv[2], argv[3]);
    } else if (argc == 5 && !strcmp(argv[1], "layers")) {
        uint8_t* b = slurp(argv[2], sizeof canvases);
        memcpy(canvases, b, sizeof canvases);
        free(b);
        mask = (unsigned)strtoul(argv[3], NULL, 0);
        snprintf(path, sizeof path, "%s", argv[4]);
    } else {
        fprintf(stderr, "usage: vmix frame <dir> <frame> [--layers] | vmix layers <layers.rgba> <mask> <out.rgb>\n");
        return 2;
    }
    if (compose(canvases, mask, out)) {
        fprintf(stderr, "vmix: a channel overflowed 255\n");
        return 1;
    }
    spit(path, out, sizeof out);
    return 0;
}
