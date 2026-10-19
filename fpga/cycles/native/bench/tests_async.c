/* Test 8: hwBlit's lazy wait (cycles/bchisel.h, BLIT_ASYNC). A CHISEL fill and CPU work that
 * does not touch its pixels, one after the other (seq: hwBlit waits) and overlapped (lazy: hwBlit
 * returns once CHISEL has started, the sync after the work waits for what is left). lazy ~ the
 * longer of the two is the overlap; lazy ~ seq would mean none. The CPU work is ALU ops (k_alu,
 * ~1.4 cycles each) or word stores to cart RAM (k_st_sw), sized to about the fill's own time.
 * The small-op rows: 64 8x8 fills back to back (nothing to overlap but the call itself: the
 * replay of the block after each lazy op is the price), and the same with ~350 cycles of ALU
 * work between them (each op's ~500-cycle latency hidden behind the next op's work). */
#include "bench.h"

#define BIG_W BENCH_BLIT_STRIDE
#define TILES 0x10000u /* as tests_chisel.c: the small fills' corner */

static void fill_rows(uint32_t rows) { chisel_fill(BENCH_BLIT_OFF, BENCH_BLIT_STRIDE, BIG_W, rows); }
static void cpu_work(const bench_case* c) {
    if (c->arg & 1) k_st_sw(g.ram + 0x80000u, c->arg >> 1);
    else bench_sink = k_alu(c->arg >> 1);
}
static uint32_t rows_of(const bench_case* c) { return c->size / BIG_W; }

static void work(const bench_case* c) { cpu_work(c); }
static void fill(const bench_case* c) { fill_rows(rows_of(c)); }
static void seq(const bench_case* c) {
    fill_rows(rows_of(c));
    cpu_work(c);
}
static void lazy(const bench_case* c) {
    chisel_async(1);
    fill_rows(rows_of(c));
    cpu_work(c);
    chisel_async(0); /* syncs */
}

/* 64 8x8 fills; arg = ALU ops between them (0: back to back). */
static void tiles(const bench_case* c, int async) {
    if (async) chisel_async(1);
    for (uint32_t i = 0; i < c->ops; i++) {
        chisel_fill(BENCH_BLIT_OFF + TILES + i * 8u, BENCH_BLIT_STRIDE, 8, 8);
        if (c->arg) bench_sink = k_alu(c->arg);
    }
    if (async) chisel_async(0);
}
static void tiles_seq(const bench_case* c) { tiles(c, 0); }
static void tiles_lazy(const bench_case* c) { tiles(c, 1); }

/* size = the fill's bytes (rows of 512); arg = (CPU ops << 1) | stores. */
#define ALU(n) ((n) << 1)
#define ST(n) (((n) << 1) | 1u)
const bench_case bench_async_cases[] = {
    {"as.fill.64K", fill, 0, 65536, 1, 0},
    {"as.alu.64K", work, 0, 0, 1, ALU(48000)},
    {"as.seq.alu.64K", seq, 0, 65536, 1, ALU(48000)},
    {"as.lazy.alu.64K", lazy, 0, 65536, 1, ALU(48000)},
    {"as.st.64K", work, 0, 0, 1, ST(24576)},
    {"as.seq.st.64K", seq, 0, 65536, 1, ST(24576)},
    {"as.lazy.st.64K", lazy, 0, 65536, 1, ST(24576)},
    {"as.fill.8K", fill, 0, 8192, 1, 0},
    {"as.seq.alu.8K", seq, 0, 8192, 1, ALU(6000)},
    {"as.lazy.alu.8K", lazy, 0, 8192, 1, ALU(6000)},
    {"as.seq.f8.x64", tiles_seq, 0, 4096, 64, 0},
    {"as.lazy.f8.x64", tiles_lazy, 0, 4096, 64, 0},
    {"as.seq.f8w.x64", tiles_seq, 0, 4096, 64, 256},
    {"as.lazy.f8w.x64", tiles_lazy, 0, 4096, 64, 256},
    {0, 0, 0, 0, 0, 0},
};

/* An async hwBlit's own cost (64 KiB fill: it returns long before CHISEL is done), the sync
 * that then waits, and a sync with nothing pending (the NOP hwBlit a cart pays when idle). */
void bench_async_calls(void) {
    uint32_t kick[BENCH_REPEATS], wait[BENCH_REPEATS], idle[BENCH_REPEATS];
    for (int r = 0; r < BENCH_REPEATS; r++) {
        chisel_async(1);
        uint32_t t0 = bench_cycles();
        fill_rows(128);
        uint32_t t1 = bench_cycles();
        chisel_sync();
        uint32_t t2 = bench_cycles();
        chisel_sync();
        uint32_t t3 = bench_cycles();
        chisel_async(0);
        kick[r] = t1 - t0, wait[r] = t2 - t1, idle[r] = t3 - t2;
    }
    bench_record("as.kick.64K", 65536, 1, kick, BENCH_REPEATS);
    bench_record("as.sync.64K", 65536, 1, wait, BENCH_REPEATS);
    bench_record("as.sync.idle", 0, 1, idle, BENCH_REPEATS);
}
