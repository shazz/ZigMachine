/* The BARD MP3 study's bench on the sound CPU (snd-cbench, scbench.h): decode MP3_FRAMES frames of
 * every stream, and per frame print its cycles, its load on BARD at the stream's rate (an MP3 frame is
 * 1152 samples, 26.1 ms at 44.1 kHz), its soft divides and its PCM hash (the host must print the same).
 *   make snd-cbench CBENCH_SRC="cycles/sound/mp3bench.c cycles/sound/mp3a_helix.c <decoder> <streams.c>"
 * (tools/mp3_bard_bench.sh builds it). */
#include <stdio.h>

#include "mp3bench.h"
#include "scbench.h"

#ifndef MP3_FRAMES
#define MP3_FRAMES 4
#endif
#define BARD_HZ 100000000u

/* The core has no divider: libgcc's divides are a loop. These replace them (same results) and count
 * the calls, so a decoder's runtime divides show up per frame. */
static uint32_t n_div;
static uint32_t udiv(uint32_t a, uint32_t b, uint32_t *rem) {
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((a >> i) & 1u);
        if (r >= b) { r -= b; q |= 1u << i; }
    }
    n_div++;
    *rem = r;
    return q;
}
uint32_t __udivsi3(uint32_t a, uint32_t b);
uint32_t __umodsi3(uint32_t a, uint32_t b);
int32_t __divsi3(int32_t a, int32_t b);
int32_t __modsi3(int32_t a, int32_t b);
uint32_t __udivsi3(uint32_t a, uint32_t b) { uint32_t r; return udiv(a, b, &r); }
uint32_t __umodsi3(uint32_t a, uint32_t b) { uint32_t r; udiv(a, b, &r); return r; }
int32_t __divsi3(int32_t a, int32_t b) {
    uint32_t r, q = udiv(a < 0 ? -(uint32_t)a : (uint32_t)a, b < 0 ? -(uint32_t)b : (uint32_t)b, &r);
    return (a < 0) != (b < 0) ? -(int32_t)q : (int32_t)q;
}
int32_t __modsi3(int32_t a, int32_t b) {
    uint32_t r;
    udiv(a < 0 ? -(uint32_t)a : (uint32_t)a, b < 0 ? -(uint32_t)b : (uint32_t)b, &r);
    return a < 0 ? -(int32_t)r : (int32_t)r;
}

static int16_t pcm[MP3_MAX_PCM];

static int bench_stream(const mp3_stream_t *s) {
    void *d = mp3a_open();
    if (!d) return 2;
    const uint8_t *p = s->data;
    uint32_t left = s->len;
    for (int f = 0; f < MP3_FRAMES; f++) {
        int nch = 0, rate = 0;
        n_div = 0;
        cb_mark_t t0 = cb_mark();
        int n = mp3a_frame(d, &p, &left, pcm, &nch, &rate);
        uint32_t divs = n_div; /* before cb_frame, whose printf divides too */
        uint32_t c = cb_frame(f, t0, n > 0 ? (uint32_t)n : 0);
        if (n < 0) break;
        uint32_t load = n ? (uint32_t)((uint64_t)c * rate / ((uint64_t)n * (BARD_HZ / 1000u))) : 0;
        printf("MP3 %s %s %d cyc %lu rate %d ch %d load %lu.%lu %% div %lu hash %08lx\n", mp3a_name, s->name, f,
               (unsigned long)c, rate, nch, (unsigned long)(load / 10), (unsigned long)(load % 10),
               (unsigned long)divs, (unsigned long)mp3_hash(pcm, n * nch));
    }
    mp3a_close(d);
    return 0;
}

int cbench_run(void) {
    for (int i = 0; i < mp3_nstreams; i++) {
        int rc = bench_stream(&mp3_streams[i]);
        if (rc) return rc;
    }
    return 0;
}
