/* The BARD SID study's bench on the sound CPU (snd-cbench, scbench.h): start every tune and render
 * SID_FRAMES 60 Hz frames of it; per frame print its cycles, its share of BARD, its soft divides and
 * its PCM hash (tools/sid_bard_host.c prints the same). The start (cRSID's init: the tune's INIT
 * routine on the 6502, unless the tune is RSID) is timed as frame -1.
 *   make snd-cbench CBENCH_SRC="cycles/sound/sidbench.c cycles/sound/cbdiv.c <libcRSID.c> <tunes.c>"
 * (tools/sid_bard_bench.sh builds it). */
#include <stdio.h>

#include "scbench.h"
#include "sidbench.h"

#ifndef SID_FRAMES
#define SID_FRAMES 6
#endif

extern uint32_t cb_ndiv;

#ifdef SID_PROF
/* A profiling copy of cRSID (the study's, never committed) stamps its phases into these: 1 = 6502 +
 * CIA + VIC, 4 = ADSRs, 2 = oversampled waveforms, 3 = filters and output stage. */
uint32_t sidprof_acc[5], sidprof_last;
static void sid_prof_print(const char *name, int f) {
    printf("PROF %s %d cpu %lu adsr %lu wave %lu filt %lu\n", name, f, (unsigned long)sidprof_acc[1],
           (unsigned long)sidprof_acc[4], (unsigned long)sidprof_acc[2], (unsigned long)sidprof_acc[3]);
    for (int i = 0; i < 5; i++) sidprof_acc[i] = 0;
}
#else
static void sid_prof_print(const char *name, int f) { (void)name, (void)f; }
#endif

static int16_t pcm[SID_FRAME * 2];
static uint8_t copy[65536 + 128]; /* a .sid is at most a 64 KiB C64 image plus its header */

static int bench_tune(const sid_tune_t *t) {
    if (t->len > sizeof copy) return 3;
    cb_mark_t t0 = cb_mark();
    int rc = sid_start(t, copy);
    cb_frame(-1, t0, 0);
    if (rc) return rc;
    for (int f = 0; f < SID_FRAMES; f++) {
        cb_ndiv = 0;
        t0 = cb_mark();
        sid_frame(pcm);
        uint32_t divs = cb_ndiv; /* before cb_frame, whose printf divides too */
        uint32_t c = cb_frame(f, t0, SID_FRAME);
        printf("SID %s %d cyc %lu rate %d hq %d div %lu hash %08lx\n", t->name, f, (unsigned long)c, SID_RATE, SID_HQ,
               (unsigned long)divs, (unsigned long)sid_hash(pcm, SID_FRAME * 2));
        sid_prof_print(t->name, f);
    }
    return 0;
}

/* What one soft divide costs on this core: 1000 of them, operands like cRSID's per-sample ones. */
static void div_cost(void) {
    static volatile int32_t num = 123456, den = 5, sink;
    cb_mark_t t0 = cb_mark();
    for (int i = 0; i < 1000; i++) sink = num / den;
    printf("DIVCOST %lu cycles for 1000\n", (unsigned long)(cb_mark().cycles - t0.cycles));
}

int cbench_run(void) {
    div_cost();
    for (int i = 0; i < sid_ntunes; i++) {
        int rc = bench_tune(&sid_tunes[i]);
        if (rc) return rc;
    }
    return 0;
}
