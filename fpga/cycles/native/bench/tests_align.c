/* Test 11: misaligned accesses. ZIGGY traps on a misaligned lw/lh/sw/sh (mcause 4/6) and the
 * system emulates it (cycles/trap.S saves 31 registers, trap.c does it byte by byte), which was
 * measured costing ics ~8.8 Mc a frame. Each figure is one access to a hot word (the 2 KiB the
 * other tests warm), so a trapped one is the trap's cost plus its byte loads or byte stores:
 *   mis.lw.<o> / mis.sw.<o> / mis.sh.<o>   at byte offset o (0 = aligned, the baseline)
 *   mis.*.bytes                             the same done by hand with lbu/sb and shifts
 * Decides whether a fast-path trap handler (or byte code in the carts) is worth it. */
#include "bench.h"

#define HOT 0xC0000u /* tests_cpu.c's warm 2 KiB */
#define N 64         /* accesses a body: a trap is ~700 cycles */

static uint8_t* at(uint32_t off) { return g.ram + HOT + off; }

static void lw_at(const bench_case* c) { bench_sink = k_csr_rd((const volatile uint32_t*)at(c->arg), N); }
static void lw_bytes(const bench_case* c) { bench_sink = k_lw_bytes(at(c->arg), N); }
static void sw_at(const bench_case* c) { k_st_val((volatile uint32_t*)at(c->arg), N, 0x5A5A5A5Au); }
static void sw_bytes(const bench_case* c) { k_sw_bytes(at(c->arg), N, 0x5A5A5A5Au); }
static void sh_at(const bench_case* c) { k_sh_val(at(c->arg), N, 0x5A5Au); }
static void sh_bytes(const bench_case* c) { k_sh_bytes(at(c->arg), N, 0x5A5Au); }
static void warm(const bench_case* c) { (void)c, bench_sink = k_ld_seq(at(0), 512); }

const bench_case bench_align_cases[] = {
    {"mis.lw.0", lw_at, warm, N * 4, N, 0},
    {"mis.lw.1", lw_at, warm, N * 4, N, 1},
    {"mis.lw.2", lw_at, warm, N * 4, N, 2},
    {"mis.lw.3", lw_at, warm, N * 4, N, 3},
    {"mis.lw.bytes", lw_bytes, warm, N * 4, N, 1},
    {"mis.sw.0", sw_at, warm, N * 4, N, 0},
    {"mis.sw.1", sw_at, warm, N * 4, N, 1},
    {"mis.sw.2", sw_at, warm, N * 4, N, 2},
    {"mis.sw.3", sw_at, warm, N * 4, N, 3},
    {"mis.sw.bytes", sw_bytes, warm, N * 4, N, 1},
    {"mis.sh.0", sh_at, warm, N * 2, N, 0},
    {"mis.sh.1", sh_at, warm, N * 2, N, 1},
    {"mis.sh.bytes", sh_bytes, warm, N * 2, N, 1},
    {0, 0, 0, 0, 0, 0},
};
