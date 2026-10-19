/* Tests 1-3: stores, loads and read-after-write in the cart's RAM (bench.h BENCH_RAM_AT).
 * The model under test: ZIGGY's D$ is write-through with no write-allocate and HP0's bridge
 * holds no store (posted = 0), so every store waits for its DDR write (~27 cycles) whatever
 * its width or address, and ALU work after a store does not overlap it. A load costs a cycle
 * on a D$ hit (4 KiB, one way, 32-byte lines) and a DDR read on a miss.
 *
 * Buffers (offsets in the 1 MiB at g.ram): stores from 0; streaming loads and RAW-miss at
 * 0x40000; the long pointer chain at 0x80000 (128 KiB); the hot 2 KiB at 0xC0000. */
#include "bench.h"

volatile uint32_t bench_sink;

#define RAM_LD 0x40000u
#define RAM_CHASE 0x80000u
#define RAM_HOT 0xC0000u

static void st_sb(const bench_case* c) { k_st_sb(g.ram, c->ops); }
static void st_sh(const bench_case* c) { k_st_sh(g.ram, c->ops); }
static void st_sw(const bench_case* c) { k_st_sw(g.ram, c->ops); }
static void st_same(const bench_case* c) { k_st_same(g.ram, c->ops); }
static void st_stride(const bench_case* c) { k_st_stride(g.ram, c->ops, c->arg); }
static void st_alu4(const bench_case* c) { k_st_alu4(g.ram, c->ops); }
static void st_alu16(const bench_case* c) { k_st_alu16(g.ram, c->ops); }

static void ld_seq(const bench_case* c) { bench_sink = k_ld_seq(g.ram + c->arg, c->ops); }
static void ld_line(const bench_case* c) { bench_sink = k_ld_stride(g.ram + RAM_LD, c->ops, 32); }
static void ld_chase(const bench_case* c) { bench_sink = k_ld_chase(g.ram + c->arg, c->ops); }

/* A ring of `n` words 32 bytes apart (one a D$ line), each holding the next one's address. */
static void chain(uint32_t at, uint32_t n) {
    uint8_t* p = g.ram + at;
    for (uint32_t i = 0; i < n; i++) *(uint32_t*)(p + 32u * i) = (uint32_t)(uintptr_t)(p + 32u * ((i + 1) % n));
}
static void prep_chase(const bench_case* c) { chain(c->arg, c->size / 32u); }

static void raw_hot(const bench_case* c) { bench_sink = k_raw(g.ram + RAM_HOT, c->ops, 4); }
static void raw_miss(const bench_case* c) { bench_sink = k_raw(g.ram + RAM_LD, c->ops, 32); }
static void prep_hot(const bench_case* c) { (void)c, bench_sink = k_ld_seq(g.ram + RAM_HOT, 512); }

const bench_case bench_cpu_cases[] = {
    /* 1. stores: width, footprint, one word, strides, and ALU work a posted buffer could hide */
    {"st.sb.1K", st_sb, 0, 1024, 1024, 0},
    {"st.sb.16K", st_sb, 0, 16384, 16384, 0},
    {"st.sb.256K", st_sb, 0, 262144, 262144, 0},
    {"st.sh.1K", st_sh, 0, 1024, 512, 0},
    {"st.sh.16K", st_sh, 0, 16384, 8192, 0},
    {"st.sh.256K", st_sh, 0, 262144, 131072, 0},
    {"st.sw.1K", st_sw, 0, 1024, 256, 0},
    {"st.sw.16K", st_sw, 0, 16384, 4096, 0},
    {"st.sw.256K", st_sw, 0, 262144, 65536, 0},
    {"st.sw.same", st_same, 0, 16384, 4096, 0},
    {"st.sw.str32", st_stride, 0, 16384, 4096, 32},
    {"st.sw.str64", st_stride, 0, 16384, 4096, 64},
    {"st.alu0", st_sw, 0, 16384, 4096, 0},
    {"st.alu4", st_alu4, 0, 16384, 4096, 0},
    {"st.alu16", st_alu16, 0, 16384, 4096, 0},
    /* 2. loads: D$ hits, a stream (a miss a line), every load a miss, dependent hits/misses */
    {"ld.hit.2K", ld_seq, 0, 2048, 512, RAM_HOT},
    {"ld.seq.64K", ld_seq, 0, 65536, 16384, RAM_LD},
    {"ld.miss.64K", ld_line, 0, 65536, 2048, 0},
    {"ld.chase.hit", ld_chase, prep_chase, 2048, 4096, RAM_HOT},
    {"ld.chase.miss", ld_chase, prep_chase, 131072, 4096, RAM_CHASE},
    /* 3. read after write: the word's line cached (2 KiB, warmed) or not (a new line each) */
    {"raw.hit", raw_hot, prep_hot, 2048, 512, 0},
    {"raw.miss", raw_miss, 0, 65536, 2048, 0},
    {0, 0, 0, 0, 0, 0},
};
