/* ZM-X v1 on the core against its twin (tests/test_zmx.py, tests/tb/dcache_tb.cpp).
 *
 * For each op: every pair of 16 edge words, then N_RANDOM xorshift32 pairs. The core's
 * result is checked against cycles/zmx_twin.h (zmx_eval, compiled into this program),
 * and hashed: the host recomputes the same vectors through libs/zig/zmx.zig and must
 * get the same hash (tests/zmx/zmx_equiv.zig), so the RTL, the C twin and the Zig spec
 * agree bit for bit. Then dependent pairs back to back (the bypass), then encodings
 * that are no ZM-X op, each of which must trap (start.S counts and skips).
 *
 * REPORT lines, in order: one hash per op (OPS order), mismatches, traps; on the first
 * mismatch also op, a, b, core, twin. Exit 0, 1 (a mismatch), 4 (a wrong trap count). */
#include <stdint.h>

#include "zmx_twin.h"

#define DEV ((volatile uint32_t*)0xf0000000u)
#define N_RANDOM 2048u
#define N_ILLEGAL 7u

volatile uint32_t zmx_traps;

#define ZMX(f3, f7, a, b)                                                                         \
    ({                                                                                            \
        uint32_t r_ = 0xdeadbeefu;                                                                \
        __asm__ volatile(".insn r CUSTOM_0, %3, %4, %0, %1, %2" : "+r"(r_) : "r"(a), "r"(b), "i"(f3), \
                         "i"(f7));                                                                \
        r_;                                                                                       \
    })

static const uint32_t EDGES[16] = {0u,          1u,          0x7fu,       0x80u,       0xffu,       0x7fffffffu,
                                   0x80000000u, 0xffffffffu, 0x00ff00ffu, 0xff00ff00u, 0x01010101u, 0xfefefefeu,
                                   0x00010000u, 0xffff0000u, 0x0000ffffu, 0x12345678u};

static uint32_t rng = 0x2545f491u;
static uint32_t next(void) { /* xorshift32: zmx_equiv.zig's twin of it */
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

#define T8(h) T(h * 8 + 0) T(h * 8 + 1) T(h * 8 + 2) T(h * 8 + 3) T(h * 8 + 4) T(h * 8 + 5) T(h * 8 + 6) T(h * 8 + 7)
static uint32_t tex2d(uint32_t d, uint32_t a, uint32_t b) {
    switch (d) {
#define T(n) \
    case n: return ZMX(7, n, a, b);
        T8(0) T8(1) T8(2) T8(3) T8(4) T8(5) T8(6) T8(7)
#undef T
    }
    return 0;
}

/* The core: op i of OPS (tex2d's dims = the vector's index mod 64). */
static uint32_t core(unsigned op, uint32_t k, uint32_t a, uint32_t b) {
    switch (op) {
        case 0: return ZMX(0, 1, a, b);
        case 1: return ZMX(1, 1, a, b);
        case 2: return ZMX(1, 2, a, b);
        case 3: return ZMX(2, 2, a, b);
        case 4: return ZMX(3, 2, a, b);
        case 5: return ZMX(0, 3, a, b);
        case 6: return ZMX(0, 4, a, b);
        case 7: return ZMX(0, 5, a, b);
        case 8: return ZMX(0, 6, a, b);
        default: return tex2d(k & 63u, a, b);
    }
}

/* The same op's instruction word, for zmx_eval (rd, rs1, rs2 = 0: only funct3/funct7 matter). */
static uint32_t insn(unsigned op, uint32_t k) {
    static const uint8_t F3[9] = {0, 1, 1, 2, 3, 0, 0, 0, 0}, F7[9] = {1, 1, 2, 2, 2, 3, 4, 5, 6};
    uint32_t f3 = op < 9 ? F3[op] : 7u, f7 = op < 9 ? F7[op] : (k & 63u);
    return (f7 << 25) | (f3 << 12) | 0x0bu;
}

static uint32_t bad;
static void check(unsigned op, uint32_t a, uint32_t b, uint32_t got, uint32_t want) {
    if (got == want) return;
    if (!bad++) {
        uint32_t r[5] = {op, a, b, got, want};
        for (int i = 0; i < 5; i++) DEV[2] = r[i];
    }
}

static uint32_t run_op(unsigned op) {
    uint32_t h = 2166136261u;
    for (uint32_t i = 0; i < 256u + N_RANDOM; i++) {
        uint32_t a = i < 256u ? EDGES[i >> 4] : next(), b = i < 256u ? EDGES[i & 15u] : next(), want = 0;
        uint32_t got = core(op, i, a, b);
        if (!zmx_eval(insn(op, i), a, b, &want)) want = ~got; /* zmx_eval must know every op */
        check(op, a, b, got, want);
        h = (h ^ got) * 16777619u;
    }
    return h;
}

/* Dependent ops back to back: the second reads the first's rd at once (the bypass paths). */
static void chains(void) {
    for (uint32_t i = 0; i < 256u; i++) {
        uint32_t a = next(), b = next(), c = next(), r1, r2, r3, r4;
        __asm__ volatile(".insn r CUSTOM_0, 0, 3, %0, %1, %2\n .insn r CUSTOM_0, 0, 5, %0, %0, %3"
                         : "=&r"(r1) : "r"(a), "r"(b), "r"(c));
        check(100, a, b, r1, zmx_lanes(zmx_lanes(a, b, ZMX_F7_ADD8S), c, ZMX_F7_AVG8));
        __asm__ volatile(".insn r CUSTOM_0, 0, 1, %0, %1, %2\n .insn r CUSTOM_0, 1, 1, %0, %0, %3"
                         : "=&r"(r2) : "r"(a), "r"(b), "r"(c));
        check(101, a, b, r2, zmx_mulsh(zmx_mulsh(a, b, 16), c, 15));
        __asm__ volatile(".insn r CUSTOM_0, 2, 2, %0, %1, %2\n .insn r CUSTOM_0, 0, 4, %0, %3, %0\n add %0, %0, %1"
                         : "=&r"(r3) : "r"(a), "r"(b), "r"(c));
        check(102, a, b, r3, zmx_lanes(c, zmx_funnel(a, b, 2), ZMX_F7_SUB8S) + a);
        __asm__ volatile(".insn r CUSTOM_0, 7, 9, %0, %1, %2\n add %0, %0, %3\n .insn r CUSTOM_0, 0, 6, %0, %0, %0"
                         : "=&r"(r4) : "r"(a), "r"(b), "r"(c));
        uint32_t t = zmx_tex2d(a, b, 9) + c;
        check(103, a, b, r4, zmx_lanes(t, t, ZMX_F7_ADD8));
    }
}

/* Encodings next to the ops that are none: each must trap and leave rd alone. */
static void illegal(void) {
    uint32_t a = 0x01020304u, b = 0x05060708u, r[N_ILLEGAL] = {
        ZMX(0, 2, a, b),  /* funnel k = 0 */
        ZMX(2, 1, a, b),  /* mulsh funct3 2 */
        ZMX(0, 0, a, b),  /* funct7 0 */
        ZMX(0, 7, a, b),  /* funct7 7 */
        ZMX(1, 3, a, b),  /* add8s funct3 1 */
        ZMX(7, 64, a, b), /* tex2d with funct7 bit 6 */
        ZMX(4, 5, a, b),  /* avg8 funct3 4 */
    };
    for (unsigned i = 0; i < N_ILLEGAL; i++) check(200 + i, a, b, r[i], 0xdeadbeefu);
}

int main(void) {
    for (unsigned op = 0; op < 10; op++) DEV[2] = run_op(op);
    chains();
    uint32_t before = zmx_traps;
    illegal();
    uint32_t traps = zmx_traps - before;
    DEV[2] = bad;
    DEV[2] = traps;
    return bad ? 1 : traps != N_ILLEGAL ? 4 : 0;
}
