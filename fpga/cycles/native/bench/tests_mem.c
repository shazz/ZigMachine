/* Test 4: clearing and copying N bytes, four ways, at 64 B, 1, 8, 32 and 64 KiB (ops = bytes,
 * so cycles/op is cycles a byte):
 *   lib    the system's memset/memcpy (cycles/zm_string.c, the table's rt entries): word stores
 *   word   a hand-unrolled word loop (kern_store.S): the floor for CPU stores
 *   chisel CHISEL through the system's hwBlit (FILL, or BLIT from the cart's RAM, SRC_ABS)
 *   raw    CHISEL started straight from the cart and waited on (fill only): hwBlit's share
 * The CPU variants write the cart's RAM; CHISEL can only write VRAM (test 6 shows whether the
 * CPU pays more there). CHISEL's rectangles are BENCH_BLIT_STRIDE (512) wide, so each size is
 * exactly W x H. Break-even: the size where chisel's cycles fall below lib's. */
#include "bench.h"

#define RAM_SRC 0x40000u /* copies read here (64 KiB) and write g.ram */

typedef void* (*memset_fn)(void*, int, uint32_t);
typedef void* (*memcpy_fn)(void*, const void*, uint32_t);

static uint32_t w_of(uint32_t n) { return n < BENCH_BLIT_STRIDE ? n : BENCH_BLIT_STRIDE; }

static void ms_lib(const bench_case* c) { SYS(ZM_RT_memset, memset_fn)(g.ram, 0x5A, c->size); }
static void ms_word(const bench_case* c) { k_st_sw(g.ram, c->size / 4u); }
static void ms_chisel(const bench_case* c) {
    uint32_t w = w_of(c->size);
    chisel_fill(BENCH_BLIT_OFF, BENCH_BLIT_STRIDE, w, c->size / w);
}
static void ms_raw(const bench_case* c) {
    uint32_t w = w_of(c->size);
    chisel_go_fill(BENCH_BLIT_OFF, BENCH_BLIT_STRIDE, w, c->size / w);
    chisel_wait();
}
static void mc_lib(const bench_case* c) { SYS(ZM_RT_memcpy, memcpy_fn)(g.ram, g.ram + RAM_SRC, c->size); }
static void mc_word(const bench_case* c) { k_cpy_w(g.ram, g.ram + RAM_SRC, c->size / 4u); }
static void mc_chisel(const bench_case* c) {
    uint32_t w = w_of(c->size);
    chisel_copy(BENCH_BLIT_OFF, BENCH_RAM_AT + RAM_SRC, BENCH_BLIT_STRIDE, w, c->size / w);
}

/* Test 6: the same stores into VRAM (the region FRESCO snoops for its registers and palettes,
 * not for pixels), and into snooped words: a palette entry and BACKGROUND, rewritten with
 * the value they hold. */
static uint8_t* vram(void) { return g.vreg + BENCH_VRAM_OFF; }
static void vr_st(const bench_case* c) { k_st_sw(vram(), c->ops); }
static void vr_ms(const bench_case* c) { SYS(ZM_RT_memset, memset_fn)(vram(), 0, c->size); }
static void vr_ld(const bench_case* c) { bench_sink = k_ld_stride(vram(), c->ops, 32); }
static void st_word(const bench_case* c) {
    volatile uint32_t* p = (volatile uint32_t*)(g.vreg + c->arg);
    k_st_val(p, c->ops, *p);
}

#define PAL3_255 (ZM_OFF_PAL + 3u * 1024u + 255u * 4u) /* plane 3's last colour */
#define SIZES(base, fn)                                                                        \
    {base ".64", fn, 0, 64, 64, 0}, {base ".1K", fn, 0, 1024, 1024, 0},                        \
        {base ".8K", fn, 0, 8192, 8192, 0}, {base ".32K", fn, 0, 32768, 32768, 0},             \
        {base ".64K", fn, 0, 65536, 65536, 0}

const bench_case bench_mem_cases[] = {
    SIZES("ms.lib", ms_lib),
    SIZES("ms.word", ms_word),
    SIZES("ms.chisel", ms_chisel),
    SIZES("ms.raw", ms_raw),
    SIZES("mc.lib", mc_lib),
    SIZES("mc.word", mc_word),
    SIZES("mc.chisel", mc_chisel),
    {"vr.st.sw.16K", vr_st, 0, 16384, 4096, 0},
    {"vr.ms.lib.64K", vr_ms, 0, 65536, 65536, 0},
    {"vr.ld.miss.64K", vr_ld, 0, 65536, 2048, 0},
    {"st.pal", st_word, 0, 16384, 4096, PAL3_255},
    {"st.reg.bg", st_word, 0, 16384, 4096, ZM_REG_BACKGROUND},
    {0, 0, 0, 0, 0, 0},
};
