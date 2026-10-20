/* Test 10: libs/zig/chisel_copy.zig's size-switched copy, cart RAM into VRAM: the CPU (the
 * system's memcpy) below COPY_MIN bytes, CHISEL above (BLIT, SRC_ABS, rows of COPY_W), as the
 * Zig does it. Both halves alone at 2 and 4 KiB (8 KiB and up: mc.lib.* / mc.chisel.*, which
 * write cart RAM and 512-wide rows), then the switch at 2, 4 and 8 KiB: cp.sw.N should be the
 * smaller of cp.lib.N and cp.chisel.N. The board's 19 Oct bench put the crossover between 1 K
 * (CPU ~1000, CHISEL 2332 cycles) and 8 K (22.5 K vs 11.6 K). */
#include "bench.h"

#define COPY_MIN 4096u /* chisel_copy.zig COPY_MIN */
#define COPY_W 4096u   /* chisel_copy.zig COPY_W */
#define SRC_OFF 0x40000u
#define DST (BENCH_BLIT_OFF + 0x20000u)

typedef void* (*memcpy_fn)(void*, const void*, uint32_t);

static void cp_lib(const bench_case* c) { SYS(ZM_RT_memcpy, memcpy_fn)(g.vreg + DST, g.ram + SRC_OFF, c->size); }
static void cp_chisel(const bench_case* c) {
    uint32_t rows = c->size / COPY_W, tail = c->size % COPY_W, src = BENCH_RAM_AT + SRC_OFF;
    if (rows) chisel_copy(DST, src, COPY_W, COPY_W, rows);
    if (tail) chisel_copy(DST + rows * COPY_W, src + rows * COPY_W, tail, tail, 1);
}
static void cp_sw(const bench_case* c) {
    if (c->size < COPY_MIN) cp_lib(c);
    else cp_chisel(c);
}

const bench_case bench_copy_cases[] = {
    {"cp.lib.2K", cp_lib, 0, 2048, 2048, 0},
    {"cp.lib.4K", cp_lib, 0, 4096, 4096, 0},
    {"cp.chisel.2K", cp_chisel, 0, 2048, 2048, 0},
    {"cp.chisel.4K", cp_chisel, 0, 4096, 4096, 0},
    {"cp.sw.2K", cp_sw, 0, 2048, 2048, 0},
    {"cp.sw.4K", cp_sw, 0, 4096, 4096, 0},
    {"cp.sw.8K", cp_sw, 0, 8192, 8192, 0},
    {0, 0, 0, 0, 0, 0},
};
