/* RAM bandwidth as a sliced job: write, read, copy (8x unrolled long-word loops) and memcpy, over a 4 KB block
 * and a 256 KB block, the Hatari build's mem_bench.c (own code, CC0) on this machine's cart RAM. MB/s, 1 MB =
 * 1048576 B. Each of the eight tests runs for a share of the job's target time. */
#include "bench.h"
#include <string.h>
#include "../../zigmachine_mem.h"

#define NTEST 8
static const u32 sizes[2] = { 4096, 262144 };
static const char *const names[NTEST] = {
    "mem_write_4k", "mem_read_4k", "mem_copy_4k", "mem_memcpy_4k",
    "mem_write_256k", "mem_read_256k", "mem_copy_256k", "mem_memcpy_256k" };

static slicer sl;
static zm_mark mark;
static u32 *a, *b;
static int test;
static u64 reps[NTEST], us[NTEST];
static volatile u32 sink;

static void wr(u32 *p, u32 n) { for (u32 i = 0; i < n; i += 8) { p[i]=p[i+1]=p[i+2]=p[i+3]=p[i+4]=p[i+5]=p[i+6]=p[i+7]=0x12345678u; } }
static u32 rd(const u32 *p, u32 n) { u32 s = 0; for (u32 i = 0; i < n; i += 8) { s+=p[i]; s+=p[i+1]; s+=p[i+2]; s+=p[i+3]; s+=p[i+4]; s+=p[i+5]; s+=p[i+6]; s+=p[i+7]; } return s; }
static void cp(u32 *d, const u32 *s, u32 n) { for (u32 i = 0; i < n; i += 8) { d[i]=s[i]; d[i+1]=s[i+1]; d[i+2]=s[i+2]; d[i+3]=s[i+3]; d[i+4]=s[i+4]; d[i+5]=s[i+5]; d[i+6]=s[i+6]; d[i+7]=s[i+7]; } }

static void begin(void) {
    sl_begin(&sl, 8, 1000000);
    mark = zm_mark_now();
    a = zm_alloc(2 * 262144u, 8);
    b = a ? a + 262144u / 4 : 0;
    test = 0;
    for (int i = 0; i < NTEST; i++) reps[i] = us[i] = 0;
}

static void one(u32 n, int kind) {
    if (kind == 0) wr(a, n);
    else if (kind == 1) sink += rd(a, n);
    else if (kind == 2) cp(b, a, n);
    else memcpy(b, a, n * 4);
}

static int step(void) {
    if (!a) return 0;
    u32 bytes = sizes[test / 4], n = bytes / 4, k = sl_unit(&sl), t0 = bench_now();
    for (u32 i = 0; i < k; i++) one(n, test % 4);
    u32 dt = bench_now() - t0;
    sl_note(&sl, dt);
    reps[test] += k; us[test] += dt;
    int enough = sl.clocked ? sl.us >= bench_target_us / NTEST : sl.slices >= FIXED_SLICES;
    if (!enough) return 1;
    if (++test == NTEST) return 0;
    sl_begin(&sl, 8, 1000000);
    return 1;
}

static void finish(bench_res *r) {
    res_clear(r);
    res_check(r, a != 0, a ? "ran" : "OUT OF MEMORY");
    for (int i = 0; i < NTEST && sl.clocked; i++)
        if (us[i]) res_val(r, names[i], "MB/s", (u64)((double)reps[i] * sizes[i / 4] * 1000.0 * 1e6 / (1048576.0 * (double)us[i])));
    zm_release(mark);
}

const bench_job job_mem = { "mem", "RAM read/write/copy", begin, step, finish };
