/* Test 5: many tiny CHISEL ops against one big one of the same bytes (4 KiB): what an op's
 * setup and hwBlit's round trip cost (ops = blits, size = bytes drawn).
 * Test 7: contention. CHISEL is started straight (chisel_go_fill) on a 64 KiB fill (~120 Kc at
 * the fitted 1.85 c/B), and the CPU stores or loads meanwhile; each figure is timed inside the
 * body, so these are logged through bench_record, not bench_run. */
#include "bench.h"

#define TILES 0x10000u /* region offset added to BENCH_BLIT_OFF: the tiny ops' corner */

static void fills(const bench_case* c) {
    uint32_t side = c->arg, per_row = BENCH_BLIT_STRIDE / side;
    for (uint32_t i = 0; i < c->ops; i++) {
        uint32_t x = (i % per_row) * side, y = (i / per_row) * side;
        chisel_fill(BENCH_BLIT_OFF + TILES + y * BENCH_BLIT_STRIDE + x, BENCH_BLIT_STRIDE, side, side);
    }
}
static void copies(const bench_case* c) {
    uint32_t side = c->arg, per_row = BENCH_BLIT_STRIDE / side;
    for (uint32_t i = 0; i < c->ops; i++) {
        uint32_t x = (i % per_row) * side, y = (i / per_row) * side, at = y * BENCH_BLIT_STRIDE + x;
        chisel_copy(BENCH_BLIT_OFF + TILES + at, BENCH_RAM_AT + at, BENCH_BLIT_STRIDE, side, side);
    }
}
static void raw_fills(const bench_case* c) {
    uint32_t side = c->arg;
    for (uint32_t i = 0; i < c->ops; i++) {
        chisel_go_fill(BENCH_BLIT_OFF + TILES + i * side, BENCH_BLIT_STRIDE, side, side);
        chisel_wait();
    }
}

const bench_case bench_chisel_cases[] = {
    {"ch.fill8.x64", fills, 0, 4096, 64, 8},
    {"ch.fill16.x16", fills, 0, 4096, 16, 16},
    {"ch.fill64.x1", fills, 0, 4096, 1, 64},
    {"ch.copy8.x64", copies, 0, 4096, 64, 8},
    {"ch.copy16.x16", copies, 0, 4096, 16, 16},
    {"ch.copy64.x1", copies, 0, 4096, 1, 64},
    {"ch.raw.fill8.x64", raw_fills, 0, 4096, 64, 8},
    {0, 0, 0, 0, 0, 0},
};

/* --- test 7 ------------------------------------------------------------------------------ */
enum { CPU_NONE, CPU_ST, CPU_LD };
#define BIG_W BENCH_BLIT_STRIDE
#define BIG_H 128u /* 64 KiB */
#define CPU_OPS 1024u
static uint32_t still_busy; /* runs where CHISEL outlasted the CPU loop: the overlap was real */

static void cpu_work(int what) {
    if (what == CPU_ST) k_st_sw(g.ram, CPU_OPS);
    if (what == CPU_LD) bench_sink = k_ld_stride(g.ram + 0x40000u, CPU_OPS, 32);
}

/* with_fill: the CPU's loop while CHISEL fills; inner: time only the CPU's loop, else the
 * whole op from GO to BUSY falling. */
static uint32_t once(int what, int with_fill, int inner) {
    uint32_t t0 = bench_cycles(), t1, t2;
    if (with_fill) chisel_go_fill(BENCH_BLIT_OFF, BENCH_BLIT_STRIDE, BIG_W, BIG_H);
    t1 = bench_cycles();
    cpu_work(what);
    t2 = bench_cycles();
    if (with_fill && what != CPU_NONE && (*(volatile uint32_t*)NATIVE_ZMB_WINDOW >> 31)) still_busy++;
    if (with_fill) chisel_wait();
    return inner ? t2 - t1 : bench_cycles() - t0;
}

static void series(const char* name, uint32_t size, uint32_t ops, int what, int with_fill, int inner) {
    uint32_t v[BENCH_REPEATS];
    for (int r = 0; r < BENCH_REPEATS; r++) v[r] = once(what, with_fill, inner);
    bench_record(name, size, ops, v, BENCH_REPEATS);
}

void bench_contention(void) {
    still_busy = 0;
    series("cn.st.alone", CPU_OPS * 4u, CPU_OPS, CPU_ST, 0, 1);
    series("cn.st.fill", CPU_OPS * 4u, CPU_OPS, CPU_ST, 1, 1);
    series("cn.ld.alone", CPU_OPS * 32u, CPU_OPS, CPU_LD, 0, 1);
    series("cn.ld.fill", CPU_OPS * 32u, CPU_OPS, CPU_LD, 1, 1);
    series("cn.fill.alone", BIG_W * BIG_H, 1, CPU_NONE, 1, 0);
    series("cn.fill.st", BIG_W * BIG_H, 1, CPU_ST, 1, 0);
    series("cn.fill.ld", BIG_W * BIG_H, 1, CPU_LD, 1, 0);
    char b[64], *p = fmt_str(b, "ZMBENCH-INFO contention busy_after_cpu=");
    p = fmt_u32(p, still_busy);
    p = fmt_str(p, "/28");
    *p = 0;
    log_text(b);
}
