/* The texture-class bench of KESTREL_NEXT_ISA.md step 1-2 (tests/zmx_bench.py): the loops
 * the note counted (appendix), at full frame size, on the core in Verilator with a DDR-like
 * read latency (dcache_tb's read wait), to measure what the D$ geometry and ZM-X change.
 *
 *   roto64 / roto128 / roto256   a 320x200 rotozoom (rotated 30 degrees, zoom 1.25) over an
 *                                8-bit texture of 4 / 16 / 64 KiB
 *   voxel128 / voxel256          a Comanche voxel landscape, 320 columns x 96 steps, height
 *                                and colour maps of 2 x 16 / 2 x 64 KiB, spans drawn to the frame
 * Built twice: plain rv32im (what GCC makes of the C), and -DZMX (tex2d for the texel index,
 * mulsh for the Q16 scaling: the ZM-X core only). REPORT, per kernel: id * 1000000 + kcycles
 * of one frame (warm: the second of two), then id * 1000000 + D$ refills of it (in 10s). */
#include <stdint.h>

#include "zmx_twin.h"

#define DEV ((volatile uint32_t*)0xf0000000u)
#define FB ((uint8_t*)0x40300000u)  /* 320 x 200 */
#define TEX ((uint8_t*)0x40200000u) /* up to 64 KiB */
#define CMAP ((uint8_t*)0x40210000u)
#define W 320
#define H 200

#ifdef ZMX
#define TEXEL(lw, u, v) \
    ({ uint32_t r_; __asm__(".insn r CUSTOM_0, 7, %3, %0, %1, %2" : "=r"(r_) : "r"(u), "r"(v), "i"(ZMX_DIMS(lw, lw))); r_; })
#define MULSH(a, b) ({ int32_t r_; __asm__(".insn r CUSTOM_0, 0, 1, %0, %1, %2" : "=r"(r_) : "r"(a), "r"(b)); r_; })
#else
#define TEXEL(lw, u, v) ((((v) >> 16) & ((1u << (lw)) - 1u)) << (lw) | (((u) >> 16) & ((1u << (lw)) - 1u)))
#define MULSH(a, b) ((int32_t)(((int64_t)(a) * (b)) >> 16))
#endif

#define ROTO(lw)                                                                     \
    static void roto##lw(void) {                                                     \
        const uint32_t du = 45403u, dv = 26214u; /* 1.25 * (cos 30, sin 30), Q16 */  \
        uint32_t ru = 0x01230000u, rv = 0x00450000u;                                 \
        for (int y = 0; y < H; y++, ru -= dv, rv += du) {                            \
            uint8_t* d = FB + y * W;                                                 \
            uint32_t u = ru, v = rv;                                                 \
            for (int x = 0; x < W; x++, u += du, v += dv) d[x] = TEX[TEXEL(lw, u, v)]; \
        }                                                                            \
    }
ROTO(6)
ROTO(7)
ROTO(8)

static int32_t invz[96]; /* Q16 1/z for the 96 steps: the table every voxel engine keeps */

#define VOXEL(lw)                                                                          \
    static void voxel##lw(void) {                                                          \
        for (int x = 0; x < W; x++) {                                                      \
            int32_t dx = (x - W / 2) * 410, dy = 65536; /* the ray: 60-degree fan, Q16 */  \
            uint32_t px = 0x00400000u, py = 0x00100000u;                                   \
            int ybot = H;                                                                  \
            for (int s = 1; s < 96 && ybot > 0; s++) {                                     \
                px += (uint32_t)dx, py += (uint32_t)dy;                                    \
                uint32_t t = TEXEL(lw, px, py);                                            \
                int y = 60 + MULSH((int32_t)(150 - TEX[t]), invz[s]);                 \
                if (y < 0) y = 0;                                                          \
                if (y >= ybot) continue;                                                   \
                uint8_t c = CMAP[t];                                                       \
                for (uint8_t* p = FB + y * W + x; y < ybot; ybot--, p += W) *p = c;        \
            }                                                                              \
        }                                                                                  \
    }
VOXEL(7)
VOXEL(8)

static void fill(void) {
    uint32_t r = 0x9e3779b9u;
    for (uint32_t i = 0; i < 65536u; i++) {
        r ^= r << 13, r ^= r >> 17, r ^= r << 5;
        TEX[i] = (uint8_t)((i ^ (i >> 7)) + (r & 15u)); /* a height field with noise */
        CMAP[i] = (uint8_t)r;
    }
    for (int s = 1; s < 96; s++) invz[s] = (int32_t)(6553600u / (uint32_t)(s + 4)); /* Q16 of 100 / z */
}

static void measure(uint32_t id, void (*k)(void)) {
    k(); /* cold: tables, code */
    uint32_t c0 = DEV[1], r0 = DEV[9];
    k();
    uint32_t c1 = DEV[1], r1 = DEV[9];
    DEV[2] = id * 1000000u + (c1 - c0) / 1000u;
    DEV[2] = id * 1000000u + (r1 - r0) / 10u;
}

int main(void) {
    fill();
    measure(1, roto6);
    measure(2, roto7);
    measure(3, roto8);
    measure(4, voxel7);
    measure(5, voxel8);
    return 0;
}
