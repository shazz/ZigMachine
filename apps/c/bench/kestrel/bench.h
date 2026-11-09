/* The benchmark cart's kernel interface: every benchmark is a job that runs in slices.
 * Own code, CC0. A slice is sized to about SLICE_US so a frame never holds the machine for long
 * (the glass calls a frame that finishes nothing for 2 s a stall). */
#ifndef BENCH_H
#define BENCH_H

typedef unsigned int u32;
typedef unsigned long long u64;

#define BENCH_MAX_VALS 8
#define SLICE_US 8000u          /* wanted length of one slice */
#define FIXED_SLICES 2u         /* a host with no clock: this much fixed work, then "no clock" */

typedef struct { const char *name, *unit; u64 milli; } bench_val; /* value x 1000 */
typedef struct {
    int n;                      /* values in v[] (0 = none: no clock) */
    int check_ok;               /* the kernel's own self-check passed */
    char check[48];             /* what was checked, or what failed */
    bench_val v[BENCH_MAX_VALS];
} bench_res;

typedef struct {
    const char *id;             /* log name, e.g. "coremark" */
    const char *label;          /* the screen's name for it */
    void (*begin)(void);
    int (*step)(void);          /* one slice; 1 = more to do */
    void (*finish)(bench_res *r);
} bench_job;

extern const bench_job *const bench_jobs[];
extern const int bench_njobs;
extern u32 bench_target_us;     /* measured time wanted per job */
extern int bench_break;         /* harness-only: 1 = corrupt a check value, 2 = corrupt LINPACK's solution */

u32 bench_now(void);            /* env.hostMicros(), 0 = no clock */
int bench_has_clock(void);

/* Slice sizing: work units a slice, grown or shrunk toward SLICE_US from what the last one took. */
typedef struct { u32 unit, max, slices; u64 work, us; int clocked; } slicer;
void sl_begin(slicer *s, u32 first_unit, u32 max_unit);
u32 sl_unit(const slicer *s);
void sl_note(slicer *s, u32 us);       /* the timed part of the slice just run */
int sl_more(const slicer *s);

/* Captured stdout of the benchmark's own printf (rt.c). */
extern char rt_out[];
void rt_out_reset(void);
void rt_heap_reset(void);
int rt_has_line(const char *needle);

/* result helpers */
void res_clear(bench_res *r);
void res_val(bench_res *r, const char *name, const char *unit, u64 milli);
void res_check(bench_res *r, int ok, const char *what);

/* Two builds of the same source: _d (double) and _f (float). */
extern const bench_job job_coremark, job_dhry, job_whet_d, job_whet_f, job_lin_d, job_lin_f, job_mem;
#endif
