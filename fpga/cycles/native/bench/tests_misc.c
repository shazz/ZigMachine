/* Test 6 (reads): an uncached register load, the latency of every status poll the system
 * makes (vseq.c spins on FRESCO's READY / DRAINED / PAINTED, bblit.c on CHISEL's BUSY).
 * Test 8: compute baselines, to read the memory figures against.
 * Test 10: the I$: a loop body that fits (8 KiB) against one that cannot (24 KiB). */
#include "bench.h"

static void csr_rd(const bench_case* c) { bench_sink = k_csr_rd((const volatile uint32_t*)c->arg, c->ops); }

static void alu(const bench_case* c) { bench_sink = k_alu(c->ops); }
static void mul(const bench_case* c) { bench_sink = k_mul(c->ops); }
static void div(const bench_case* c) { bench_sink = k_div(c->ops); }

#ifdef __riscv_flen /* the FPU core (ZM_FPU=1): f32 is the hardware's, a dependent chain */
static void f32_add(const bench_case* c) { bench_sink = (uint32_t)k_fadd(c->ops); }
static void f32_mul(const bench_case* c) { bench_sink = (uint32_t)k_fmul(c->ops); }
static void f32_div(const bench_case* c) { bench_sink = (uint32_t)k_fdiv(c->ops); }
#endif /* else f32 is libgcc's soft-float (below), as a cart without the FPU pays it */

/* A chain of ops in registers; the empty asm keeps each result live and in order, so
 * nothing is folded or hoisted. f64 is always soft-float (RV32F has no D). */
#define CHAIN(T, name, op)                                                       \
    static void name(const bench_case* c) {                                      \
        T x = (T)(c->arg + 1u), y = (T)1;                                        \
        __asm__ volatile("" : "+r"(y)); /* opaque: x * 1 and x / 1 would fold */ \
        for (uint32_t i = 0; i < c->ops; i++) {                                  \
            x = x op y;                                                          \
            __asm__ volatile("" : "+r"(x));                                      \
        }                                                                        \
        bench_sink = (uint32_t)x;                                                \
    }
CHAIN(double, f64_add, +)
CHAIN(double, f64_mul, *)
CHAIN(double, f64_div, /)
#ifndef __riscv_flen
CHAIN(float, f32_add, +)
CHAIN(float, f32_mul, *)
CHAIN(float, f32_div, /)
#endif

static void ic_fit(const bench_case* c) { bench_sink = k_icache_fit(c->arg); }
static void ic_over(const bench_case* c) { bench_sink = k_icache_over(c->arg); }

const bench_case bench_misc_cases[] = {
    {"csr.cycles", csr_rd, 0, 0, 1024, NATIVE_CSR_CYCLES},
    {"csr.zmv.status", csr_rd, 0, 0, 1024, NATIVE_CSR_ZMV_STATUS},
    {"csr.zmb.status", csr_rd, 0, 0, 1024, NATIVE_ZMB_WINDOW},
    {"alu.add", alu, 0, 0, 8192, 0},
    {"alu.mul", mul, 0, 0, 1024, 0},
    {"alu.div", div, 0, 0, 1024, 0},
    {"f32.add", f32_add, 0, 0, 1024, 0},
    {"f32.mul", f32_mul, 0, 0, 1024, 0},
    {"f32.div", f32_div, 0, 0, 1024, 0},
    {"f64.add", f64_add, 0, 0, 256, 0},
    {"f64.mul", f64_mul, 0, 0, 256, 0},
    {"f64.div", f64_div, 0, 0, 256, 0},
    {"ic.fit.8K", ic_fit, 0, 0, 8192, 4},
    {"ic.over.24K", ic_over, 0, 0, 12288, 2},
    {0, 0, 0, 0, 0, 0},
};
