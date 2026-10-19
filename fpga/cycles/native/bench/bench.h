/* ZIGGY bench (cycles/native/bench/, decisions.md 2026-10-18): a native KESTREL cart that times
 * the board's memory and bus paths with the SoC's own cycle counter, so the store-cost model
 * (every store a blocking ~27-cycle DDR write, memset ~60 cycles a word, CHISEL ~1.85 cycles a
 * byte, ~1.09 Mc a FRESCO plane) is measured instead of fitted.
 *
 * The board firmware runs the cart in M-mode (the core has the seal, but nothing mret's to U),
 * and ZIGGY takes no interrupts, so a test reads ZMCycles (soc/zm_cycles.py) directly and
 * nothing preempts it. One test a frame; the results go to the screen and, as ZMBENCH lines,
 * into a log at the start of the cart's .bss (log.c), which the ARM reads through /dev/mem
 * (fpga/tools/bench_collect.py). */
#ifndef ZM_BENCH_H
#define ZM_BENCH_H

#include <stdint.h>

#include "native.h"
#include "zm_memmap.h"

/* The counters, in soc/zm_cycles.py COUNTERS order (one uncached load each). */
enum { C_CYC, C_IACK, C_IWAIT, C_DRD, C_DWR, C_DWAIT, C_N };
static inline uint32_t bench_cycles(void) { return *(volatile uint32_t*)NATIVE_CSR_CYCLES; }
static inline uint32_t bench_counter(int i) { return ((volatile uint32_t*)NATIVE_CSR_CYCLES)[i]; }
static inline uint32_t bench_vbls(void) { return *(volatile uint32_t*)NATIVE_CSR_ZMV_FRAME; }

/* Where the tests work, all in the shared memory (the wasm machine's linear memory). */
#define BENCH_TEXT_AT ZM_CART_RAM_BASE                /* the ROM's text scratch: 4 KiB */
#define BENCH_RAM_AT (ZM_CART_RAM_BASE + 0x1000u)     /* cart RAM: 1 MiB of buffers */
#define BENCH_RAM_BYTES 0x100000u
#define BENCH_CART_HIGH (BENCH_RAM_AT + BENCH_RAM_BYTES) /* what the cart owns (cart_high) */
#define BENCH_VRAM_OFF (ZM_OFF_VRAM + 0x40000u)       /* region offset: CPU stores, past 4 planes */
#define BENCH_BLIT_OFF (ZM_OFF_VRAM + 0x80000u)       /* region offset: CHISEL's destinations */
#define BENCH_BLIT_STRIDE 512u                        /* any size up to 64 KiB is W x H exactly */

typedef struct bench_ctx {
    struct w2c_env* env;
    uint8_t* mem;  /* the shared memory's byte 0 */
    uint8_t* ram;  /* mem + BENCH_RAM_AT */
    uint8_t* vreg; /* mem + HW_VIDEO_BASE: registers, blitter block, palettes, VRAM */
    uint32_t gui;  /* the ROM's drawing context over plane 0 */
} bench_ctx;
extern bench_ctx g;
extern volatile uint32_t bench_sink; /* where a kernel's result goes, so it is not dropped */

/* A test: `run` is the timed body, `prep` (optional) runs once before the repeats. */
typedef struct bench_case {
    const char* name;
    void (*run)(const struct bench_case* c);
    void (*prep)(const struct bench_case* c);
    uint32_t size; /* bytes the body touches (0: none), for MB/s */
    uint32_t ops;  /* what the body counts (stores, loads, bytes, blits...) */
    uint32_t arg;  /* the body's own parameter */
} bench_case;

typedef struct bench_result {
    const char* name;
    uint32_t size, ops;
    uint32_t min, med;    /* cycles, the calibration (an empty body) subtracted */
    uint32_t dwait, dwr;  /* data-bus wait cycles and writes, of the fastest repeat */
} bench_result;

#define BENCH_REPEATS 7
#define BENCH_MAX_RESULTS 128

/* run.c: time `c` BENCH_REPEATS times, keep and log the result. */
void bench_calibrate(void);
const bench_result* bench_run(const bench_case* c);
/* Log a figure measured elsewhere (the frame tests): cycles min/median over n samples. */
void bench_record(const char* name, uint32_t size, uint32_t ops, uint32_t* samples, int n);
extern bench_result bench_results[BENCH_MAX_RESULTS];
extern int bench_nresults;
uint32_t bench_median(uint32_t* v, int n); /* sorts v */

/* The test tables (tests_*.c), each ended by a NULL name. */
extern const bench_case bench_cpu_cases[];
extern const bench_case bench_mem_cases[];
extern const bench_case bench_chisel_cases[];
extern const bench_case bench_misc_cases[];
extern const bench_case bench_align_cases[];
void bench_contention(void); /* test 7: timed inside its bodies (tests_chisel.c) */

/* log.c: the ZMBENCH lines, readable by the ARM at a fixed DDR address. */
void log_begin(void);
void log_line(const bench_result* r);
void log_text(const char* s); /* a line of its own ("ZMBENCH-INFO ...") */
void log_done(void);
char* fmt_u32(char* p, uint32_t v);
char* fmt_str(char* p, const char* s);
char* fmt_fixed1(char* p, uint32_t num, uint32_t den); /* num/den with one decimal */

/* chisel.c: CHISEL through the system's hwBlit (as every cart does) or started directly. */
void chisel_fill(uint32_t off, uint32_t stride, uint32_t w, uint32_t h);
void chisel_copy(uint32_t off, uint32_t src_abs, uint32_t stride, uint32_t w, uint32_t h);
void chisel_go_fill(uint32_t off, uint32_t stride, uint32_t w, uint32_t h); /* no wait */
void chisel_wait(void);

/* planes.c: the frame tests, one frame each, driven from main.c's frame(). */
int planes_frame(void); /* 1 while it still needs frames */
uint32_t planes_mask(void);

/* screen.c: the results, a page at a time. */
void screen_progress(int done, int total);
void screen_page(int page);
int screen_pages(void);

/* The cycles of body(c), the counter read right before the call and right after it. */
uint32_t k_time(void (*body)(const bench_case*), const bench_case* c);
/* The asm kernels (kern_*.S). Counts are of the body's unit (stores, loads, ops). */
void k_st_sb(uint8_t* p, uint32_t n);
void k_st_sh(uint8_t* p, uint32_t n);
void k_st_sw(uint8_t* p, uint32_t n);
void k_st_same(uint8_t* p, uint32_t n);
void k_st_val(volatile uint32_t* p, uint32_t n, uint32_t v);
void k_st_stride(uint8_t* p, uint32_t n, uint32_t stride);
void k_st_alu4(uint8_t* p, uint32_t n);
void k_st_alu16(uint8_t* p, uint32_t n);
uint32_t k_ld_seq(const uint8_t* p, uint32_t n);
uint32_t k_ld_stride(const uint8_t* p, uint32_t n, uint32_t stride);
uint32_t k_ld_chase(const uint8_t* p, uint32_t n);
uint32_t k_raw(uint8_t* p, uint32_t n, uint32_t stride);
void k_cpy_w(uint8_t* d, const uint8_t* s, uint32_t n);
uint32_t k_csr_rd(const volatile uint32_t* p, uint32_t n);
void k_sh_val(volatile void* p, uint32_t n, uint32_t v);
void k_sw_bytes(uint8_t* p, uint32_t n, uint32_t v);
void k_sh_bytes(uint8_t* p, uint32_t n, uint32_t v);
uint32_t k_lw_bytes(const uint8_t* p, uint32_t n);
uint32_t k_alu(uint32_t n);
uint32_t k_mul(uint32_t n);
uint32_t k_div(uint32_t n);
uint32_t k_icache_fit(uint32_t n);
uint32_t k_icache_over(uint32_t n);
#ifdef __riscv_flen
float k_fadd(uint32_t n);
float k_fmul(uint32_t n);
float k_fdiv(uint32_t n);
#endif

#endif
