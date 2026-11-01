/* ZM-X v1's software twin in C (fpga/review/KESTREL_NEXT_ISA.md 1.2-1.3): the integer
 * semantics the core's ZmXPlugin / ZmMulPlugin implement, written once for the board side.
 * It is what a cart runs where the instructions are absent: the native host and the sim
 * (the cart's env.zm* imports resolve to rom.wasm's twins, libs/zig/zmx.zig, the same
 * integers), and trap.c's illegal-instruction fallback on a bitstream without ZM-X.
 * tests/test_zmx.py runs every op on the core and checks it against this file and
 * against libs/zig/zmx.zig, so the three cannot drift.
 *
 * The encoding (custom-0, opcode 0x0B), the one table every user agrees on:
 *   funct7 1  funct3 0/1  mulsh   bits [47:16] / [46:15] of the signed 64-bit product
 *   funct7 2  funct3 k    funnel  (rs1 >> 8k) | (rs2 << (32 - 8k)), k = 1..3
 *   funct7 3..6 funct3 0  add8s, sub8s, avg8 (floor), add8: four unsigned byte lanes
 *   funct3 7, funct7 = (logW - 3) | (logH - 3) << 3 (bit 6 clear): tex2d */
#ifndef ZM_ZMX_TWIN_H
#define ZM_ZMX_TWIN_H

#include <stdint.h>

#define ZMX_F7_MULSH 1u
#define ZMX_F7_FUNNEL 2u
#define ZMX_F7_ADD8S 3u
#define ZMX_F7_SUB8S 4u
#define ZMX_F7_AVG8 5u
#define ZMX_F7_ADD8 6u
#define ZMX_F3_TEX2D 7u
#define ZMX_DIMS(logw, logh) ((((logw) - 3u) & 7u) | ((((logh) - 3u) & 7u) << 3)) /* tex2d's funct7 */

/* shift 16 (funct3 0) or 15 (funct3 1); an arithmetic shift of the exact product, truncated */
static inline uint32_t zmx_mulsh(uint32_t a, uint32_t b, unsigned shift) {
    return (uint32_t)(uint64_t)(((int64_t)(int32_t)a * (int32_t)b) >> shift);
}

static inline uint32_t zmx_tex2d(uint32_t u, uint32_t v, uint32_t dims) {
    uint32_t logw = (dims & 7u) + 3u, logh = ((dims >> 3) & 7u) + 3u;
    return (((v >> 16) & ((1u << logh) - 1u)) << logw) | ((u >> 16) & ((1u << logw) - 1u));
}

static inline uint32_t zmx_funnel(uint32_t lo, uint32_t hi, unsigned k) { /* k = 1..3 */
    return (lo >> (8u * k)) | (hi << (32u - 8u * k));
}

/* One byte-lane op over the four lanes: op 3 add8s, 4 sub8s, 5 avg8, 6 add8 (the funct7). */
static inline uint32_t zmx_lanes(uint32_t a, uint32_t b, unsigned op) {
    uint32_t r = 0;
    for (unsigned i = 0; i < 32; i += 8) {
        uint32_t x = (a >> i) & 255u, y = (b >> i) & 255u, s = x + y, l;
        if (op == ZMX_F7_ADD8S) l = s > 255u ? 255u : s;
        else if (op == ZMX_F7_SUB8S) l = x > y ? x - y : 0u;
        else if (op == ZMX_F7_AVG8) l = s >> 1;
        else l = s & 255u;
        r |= l << i;
    }
    return r;
}

/* The op an encoding names, for trap.c: 1 and *rd set, or 0 when it is no ZM-X op (still illegal). */
static inline int zmx_eval(uint32_t insn, uint32_t a, uint32_t b, uint32_t* rd) {
    uint32_t f3 = (insn >> 12) & 7u, f7 = insn >> 25;
    if ((insn & 0x7fu) != 0x0bu) return 0;
    if (f3 == ZMX_F3_TEX2D) return f7 < 64u ? (*rd = zmx_tex2d(a, b, f7), 1) : 0;
    if (f7 == ZMX_F7_MULSH && f3 <= 1u) return *rd = zmx_mulsh(a, b, 16u - f3), 1;
    if (f7 == ZMX_F7_FUNNEL && f3 >= 1u && f3 <= 3u) return *rd = zmx_funnel(a, b, f3), 1;
    if (f7 >= ZMX_F7_ADD8S && f7 <= ZMX_F7_ADD8 && f3 == 0u) return *rd = zmx_lanes(a, b, f7), 1;
    return 0;
}

#endif
