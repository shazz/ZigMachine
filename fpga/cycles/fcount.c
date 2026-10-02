/* Soft-float accounting for the `float` build (-DZM_FCOUNT). VexRiscv
 * `standard` is rv32im: every f32/f64 operation the translated carts perform is
 * a call into libgcc's soft-float routines, or into libm for sqrt and the
 * rounding functions wasm2c uses. ld --wrap routes each call through a wrapper
 * here that times it with the cycle counter and charges it to the owner on top
 * of the prof stack (prof.h). Calls made from INSIDE a wrapped routine (libm
 * calling libgcc) are not counted again: depth > 0 passes straight through.
 *
 * Each routine has a class: what an FPU would do with it. tools/cycles_report.py
 * holds the hardware cost of each class; this file only measures. */
#include "fcount.h"

#ifndef ZM_FCOUNT
void fcount_clear(void) {}
void fcount_calibrate(void) {}
void fcount_print_frame(void) {}
void fcount_print_totals(void) {}
#else
#include <stdio.h>
#include <string.h>

#include "prof.h"

/* The class list is the report's: keep tools/cycles_report.py CLASSES in step. */
#define FCLASSES(C) C(FADD) C(FMUL) C(FDIV) C(FSQRT) C(FCMP) C(FCVT) C(FROUND) C(FNEG) C(F64INT) \
    C(FD) C(DADD) C(DMUL) C(DDIV) C(DSQRT) C(DCMP) C(DCVT) C(DROUND) C(DNEG) C(D64INT)
#define AS_ENUM(c) c,
enum { FCLASSES(AS_ENUM) NCLASS };

typedef long long i64;
typedef unsigned long long u64_;
/* X(<name>, class, return, (params), (args)). The Makefile turns every X line
 * into -Wl,--wrap=<name>, so this table IS the wrap list. */
#define FOPS(X) \
    X(__addsf3, FADD, float, (float a, float b), (a, b)) X(__subsf3, FADD, float, (float a, float b), (a, b)) \
    X(__mulsf3, FMUL, float, (float a, float b), (a, b)) X(__divsf3, FDIV, float, (float a, float b), (a, b)) \
    X(__negsf2, FNEG, float, (float a), (a)) \
    X(__eqsf2, FCMP, int, (float a, float b), (a, b)) X(__nesf2, FCMP, int, (float a, float b), (a, b)) \
    X(__ltsf2, FCMP, int, (float a, float b), (a, b)) X(__lesf2, FCMP, int, (float a, float b), (a, b)) \
    X(__gtsf2, FCMP, int, (float a, float b), (a, b)) X(__gesf2, FCMP, int, (float a, float b), (a, b)) \
    X(__unordsf2, FCMP, int, (float a, float b), (a, b)) \
    X(__fixsfsi, FCVT, int, (float a), (a)) X(__fixunssfsi, FCVT, unsigned, (float a), (a)) \
    X(__floatsisf, FCVT, float, (int a), (a)) X(__floatunsisf, FCVT, float, (unsigned a), (a)) \
    X(__fixsfdi, F64INT, i64, (float a), (a)) X(__fixunssfdi, F64INT, u64_, (float a), (a)) \
    X(__floatdisf, F64INT, float, (i64 a), (a)) X(__floatundisf, F64INT, float, (u64_ a), (a)) \
    X(__extendsfdf2, FD, double, (float a), (a)) X(__truncdfsf2, FD, float, (double a), (a)) \
    X(sqrtf, FSQRT, float, (float a), (a)) X(floorf, FROUND, float, (float a), (a)) \
    X(ceilf, FROUND, float, (float a), (a)) X(truncf, FROUND, float, (float a), (a)) \
    X(nearbyintf, FROUND, float, (float a), (a)) \
    X(__adddf3, DADD, double, (double a, double b), (a, b)) X(__subdf3, DADD, double, (double a, double b), (a, b)) \
    X(__muldf3, DMUL, double, (double a, double b), (a, b)) X(__divdf3, DDIV, double, (double a, double b), (a, b)) \
    X(__negdf2, DNEG, double, (double a), (a)) \
    X(__eqdf2, DCMP, int, (double a, double b), (a, b)) X(__nedf2, DCMP, int, (double a, double b), (a, b)) \
    X(__ltdf2, DCMP, int, (double a, double b), (a, b)) X(__ledf2, DCMP, int, (double a, double b), (a, b)) \
    X(__gtdf2, DCMP, int, (double a, double b), (a, b)) X(__gedf2, DCMP, int, (double a, double b), (a, b)) \
    X(__unorddf2, DCMP, int, (double a, double b), (a, b)) \
    X(__fixdfsi, DCVT, int, (double a), (a)) X(__fixunsdfsi, DCVT, unsigned, (double a), (a)) \
    X(__floatsidf, DCVT, double, (int a), (a)) X(__floatunsidf, DCVT, double, (unsigned a), (a)) \
    X(__fixdfdi, D64INT, i64, (double a), (a)) X(__fixunsdfdi, D64INT, u64_, (double a), (a)) \
    X(__floatdidf, D64INT, double, (i64 a), (a)) X(__floatundidf, D64INT, double, (u64_ a), (a)) \
    X(sqrt, DSQRT, double, (double a), (a)) X(floor, DROUND, double, (double a), (a)) \
    X(ceil, DROUND, double, (double a), (a)) X(trunc, DROUND, double, (double a), (a)) \
    X(nearbyint, DROUND, double, (double a), (a))

#define AS_OP(n, c, T, P, A) OP_##n,
enum { FOPS(AS_OP) NOP };
#define AS_CLASS(n, c, T, P, A) c,
static const unsigned char g_class[NOP] = {FOPS(AS_CLASS)};
#define AS_NAME(n, c, T, P, A) #n,
static const char* const g_name[NOP] = {FOPS(AS_NAME)};

static uint32_t g_calls[PROF_N][NOP]; /* whole run, per owner */
static uint64_t g_cyc[PROF_N][NOP];
static uint32_t g_fcalls[NCLASS];     /* this frame, CART only */
static uint32_t g_fcyc[NCLASS];
static int g_depth;

static void account(int op, uint32_t dt) {
    g_calls[prof_top][op]++;
    g_cyc[prof_top][op] += dt;
    if (prof_top != PROF_CART) return;
    g_fcalls[g_class[op]]++;
    g_fcyc[g_class[op]] += dt;
}

#define AS_WRAP(n, c, T, P, A)                         \
    T __real_##n P;                                    \
    T __wrap_##n P {                                   \
        if (g_depth) return __real_##n A;              \
        g_depth = 1;                                   \
        uint32_t t0 = board_cycles();                  \
        T r = __real_##n A;                            \
        account(OP_##n, board_cycles() - t0);          \
        g_depth = 0;                                   \
        return r;                                      \
    }
FOPS(AS_WRAP)

void fcount_clear(void) {
    memset(g_fcalls, 0, sizeof g_fcalls);
    memset(g_fcyc, 0, sizeof g_fcyc);
}

/* What one wrapper adds to its measured span: the second counter read. */
void fcount_calibrate(void) {
    uint32_t sum = 0;
    for (int i = 0; i < 1000; i++) {
        uint32_t t0 = board_cycles();
        sum += board_cycles() - t0;
    }
    printf("ZM FCAL %lu 1000\n", (unsigned long)sum);
}

void fcount_print_frame(void) {
    for (int c = 0; c < NCLASS; c++) printf(" %lu %lu", (unsigned long)g_fcalls[c], (unsigned long)g_fcyc[c]);
}

void fcount_print_totals(void) {
    for (int owner = 0; owner < PROF_N; owner++)
        for (int op = 0; op < NOP; op++)
            if (g_calls[owner][op])
                printf("ZM FL %s %d %lu %llu\n", g_name[op], owner, (unsigned long)g_calls[owner][op],
                       (unsigned long long)g_cyc[owner][op]);
}
#endif
