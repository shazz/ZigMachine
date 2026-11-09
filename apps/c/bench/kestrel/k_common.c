/* The slice scheduler's arithmetic, result helpers and the job table. Own code, CC0. */
#include "bench.h"
#include <string.h>

u32 bench_target_us = 2000000u;
int bench_break;

void sl_begin(slicer *s, u32 first_unit, u32 max_unit) {
    s->unit = first_unit; s->max = max_unit; s->slices = 0; s->work = 0; s->us = 0;
    s->clocked = bench_has_clock();
}
u32 sl_unit(const slicer *s) { return s->unit; }

/* Aim the next slice at SLICE_US, growing at most 4x a time (a slice that read 0 us is too short to size by). */
void sl_note(slicer *s, u32 us) {
    s->slices++; s->work += s->unit; s->us += us;
    if (!s->clocked) return;
    u64 want = us ? (u64)s->unit * SLICE_US / us : (u64)s->unit * 4;
    if (want > (u64)s->unit * 4) want = (u64)s->unit * 4;
    if (want < 1) want = 1;
    s->unit = want > s->max ? s->max : (u32)want;
}
int sl_more(const slicer *s) { return s->clocked ? s->us < bench_target_us : s->slices < FIXED_SLICES; }

void res_clear(bench_res *r) { r->n = 0; r->check_ok = 1; r->check[0] = 0; }
void res_val(bench_res *r, const char *name, const char *unit, u64 milli) {
    if (r->n < BENCH_MAX_VALS) { r->v[r->n].name = name; r->v[r->n].unit = unit; r->v[r->n].milli = milli; r->n++; }
}
void res_check(bench_res *r, int ok, const char *what) {
    if (!r->check_ok) return;       /* the first failure is the one reported */
    r->check_ok = ok;
    strcpy(r->check, what);
}

const bench_job *const bench_jobs[] = { &job_coremark, &job_dhry, &job_whet_d, &job_whet_f, &job_lin_d, &job_lin_f, &job_mem };
const int bench_njobs = 7;
