/* Timing a test: its body run BENCH_REPEATS times between two reads of the cycle counter
 * (k_time), the fastest and the median kept. An empty body, timed the same way first, is the
 * probe's own cost (the call through a pointer and an uncached counter load); it is subtracted
 * from every figure, and logged as calib.empty. */
#include "bench.h"

bench_ctx g;
bench_result bench_results[BENCH_MAX_RESULTS];
int bench_nresults;
static uint32_t cal_cyc, cal_wait, cal_wr;

/* The bus counters around k_time's window (they include its few instructions). */
static void snap(uint32_t* s) {
    for (int i = 1; i < C_N; i++) s[i] = bench_counter(i);
}

uint32_t bench_median(uint32_t* v, int n) {
    for (int i = 1; i < n; i++)
        for (int j = i; j > 0 && v[j - 1] > v[j]; j--) {
            uint32_t t = v[j];
            v[j] = v[j - 1], v[j - 1] = t;
        }
    return v[n / 2];
}

static uint32_t sub0(uint32_t a, uint32_t b) { return a > b ? a - b : 0; }

static bench_result* keep(const char* name, uint32_t size, uint32_t ops) {
    static bench_result spare;
    bench_result* r = bench_nresults < BENCH_MAX_RESULTS ? &bench_results[bench_nresults++] : &spare;
    r->name = name, r->size = size, r->ops = ops;
    return r;
}

typedef struct {
    uint32_t cyc[BENCH_REPEATS];
    uint32_t best, wait, wr;
} timing;

static void time_case(const bench_case* c, timing* t) {
    t->best = ~0u;
    for (int r = 0; r < BENCH_REPEATS; r++) {
        uint32_t a[C_N], b[C_N];
        snap(a);
        t->cyc[r] = k_time(c->run, c);
        snap(b);
        if (t->cyc[r] < t->best)
            t->best = t->cyc[r], t->wait = b[C_DWAIT] - a[C_DWAIT], t->wr = b[C_DWR] - a[C_DWR];
    }
}

static void __attribute__((noinline)) empty(const bench_case* c) { __asm__ volatile("" ::"r"(c)); }

void bench_calibrate(void) {
    static const bench_case cal = {"calib.empty", empty, 0, 0, 1, 0};
    timing t;
    time_case(&cal, &t);
    time_case(&cal, &t); /* the second, warm: the body's lines are in the I$ */
    bench_result* r = keep(cal.name, 0, 1);
    r->min = t.best, r->med = bench_median(t.cyc, BENCH_REPEATS), r->dwait = t.wait, r->dwr = t.wr;
    cal_cyc = t.best, cal_wait = t.wait, cal_wr = t.wr;
    log_line(r);
}

const bench_result* bench_run(const bench_case* c) {
    timing t;
    if (c->prep) c->prep(c);
    time_case(c, &t);
    bench_result* r = keep(c->name, c->size, c->ops);
    r->min = sub0(t.best, cal_cyc);
    r->med = sub0(bench_median(t.cyc, BENCH_REPEATS), cal_cyc);
    r->dwait = sub0(t.wait, cal_wait), r->dwr = sub0(t.wr, cal_wr);
    log_line(r);
    return r;
}

void bench_record(const char* name, uint32_t size, uint32_t ops, uint32_t* samples, int n) {
    bench_result* r = keep(name, size, ops);
    r->min = ~0u;
    for (int i = 0; i < n; i++)
        if (samples[i] < r->min) r->min = samples[i];
    r->med = bench_median(samples, n);
    r->dwait = 0, r->dwr = 0;
    log_line(r);
}
