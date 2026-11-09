/* CoreMark as a sliced job. Own code, CC0.
 *
 * core_*.c are EEMBC's, unmodified. A slice is ONE call of CoreMark's main() with a small fixed iteration count
 * (seeds 0,0,0x66 and size 2000, the Hatari build's arguments): its self-check compares the list, matrix and
 * state CRCs against the known values, and its timer brackets only iterate(). The score is the iterations of all
 * slices over their summed timed regions. That is NOT a reportable CoreMark (the rules ask for one run of at least
 * 10 s, which CoreMark itself flags with "ERROR! Must execute for at least 10 secs"): it is the same code, timed
 * the same way, for comparing machines. */
#include "bench.h"
#include <stdio.h>

extern int coremark_main(int argc, char *argv[]);
extern unsigned cm_last_ticks;

static slicer sl;
static int bad_crc, parameters_seen, slices_run;

static void begin(void) {
    sl_begin(&sl, 1, 100000);
    bad_crc = 0; parameters_seen = 0; slices_run = 0;
}

static int step(void) {
    char iters[12];
    snprintf(iters, sizeof iters, "%u", sl_unit(&sl));
    char *argv[] = { "coremark", "0x0", "0x0", "0x66", iters, "7", "1", "2000", 0 };
    rt_out_reset();
    coremark_main(8, argv);
    if (rt_has_line("ERROR! list crc") || rt_has_line("ERROR! matrix crc") || rt_has_line("ERROR! state crc")) bad_crc = 1;
    if (rt_has_line("2K performance run parameters")) parameters_seen = 1;
    slices_run++;    sl_note(&sl, cm_last_ticks);
    return sl_more(&sl);
}

static void finish(bench_res *r) {
    res_clear(r);
    res_check(r, parameters_seen && !bad_crc, parameters_seen ? (bad_crc ? "CRC MISMATCH" : "crc list/matrix/state ok") : "no known seed run");
    if (sl.clocked && sl.us) res_val(r, "coremark", "CoreMark", sl.work * 1000000ull * 1000 / sl.us);
}

const bench_job job_coremark = { "coremark", "CoreMark (sliced)", begin, step, finish };
