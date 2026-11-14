// ASTROLABE from C (SPIKE, docs/ARM_FPU_COPROC.md): the descriptor of machine/sdk/astro.zig and
// env.hwAstro (HW 1.18.0). A cart fills descriptors in its own memory and calls hwAstro(list, n).
#ifndef ASTRO_H
#define ASTRO_H

typedef unsigned u32;
typedef unsigned long long u64;

__attribute__((import_module("env"), import_name("hwAstro"))) extern u32 hwAstro(u32 desc, u32 count);
__attribute__((import_module("env"), import_name("hostMicros"))) extern u32 hostMicros(void);

typedef struct {
    u32 op, n, m, lda, a, b, c, rsvd, status, cycles;
    double s0, s1, s2, r;
    u32 pad[2];
} astro_desc;
_Static_assert(sizeof(astro_desc) == 80, "machine/sdk/astro.zig DESC_BYTES");

enum {
    AS_NOP = 0x00, AS_ADD = 0x01, AS_SUB, AS_MUL, AS_DIV, AS_SQRT, AS_FMA,
    AS_SIN = 0x10, AS_COS, AS_TAN, AS_ATAN2, AS_EXP, AS_LOG, AS_POW,
    AS_VADD = 0x20, AS_VMUL, AS_AXPY, AS_DOT, AS_SCAL, AS_MAP,
    AS_GEMV = 0x30, AS_GEFA, AS_GESL,
};
#define AS_F32_IN (1u << 16)
#define AS_F32_OUT (1u << 17)
enum { AS_FN_SIN = 0 };
#define AS_SERVED_ARM (1u << 8)
#define AS_MAX 48u

static inline u32 as_addr(const void* p) { return (u32)(unsigned long)p; }

static inline void as_scalar(astro_desc* d, u32 op, double a, double b) {
    *d = (astro_desc){.op = op, .s0 = a, .s1 = b};
}

static inline u64 as_bits(double d) {
    union { double d; u64 u; } x = {.d = d};
    return x.u;
}

// ulps between two finite doubles of one sign (0 when identical)
static inline u64 as_ulp(double a, double b) {
    u64 x = as_bits(a), y = as_bits(b);
    return x > y ? x - y : y - x;
}

#endif
