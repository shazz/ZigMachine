/* klystron's chorus LUT (cydchr_set, patches/cydchr.c.sed) in integers. Upstream fills lut_size entries (4 s
 * of samples: 88,200 at 22.05 kHz) with
 *     (int)(((sin(i / n * 2 pi) * 0.5 + 0.5) * (max - min) + min) * 256 * rate / 10000) % wrap
 * in double: one soft-float sin per entry on ZIGGY, ~630 Mc (6 s) per song load that enables a chorus. Here the
 * sine comes from a Q30 table (kestrel_sine.h, 1024 steps, linearly interpolated), the phase i / n is stepped
 * exactly (Bresenham: quotient and remainder of 2^32 / n), and the scale is one 32x32->64 multiply. Within
 * +-1 of upstream's entries (units of 1/256 sample). */
#include <stdint.h>
#include "kestrel_sine.h"

void kestrel_chorus_lut(int32_t *lut, int n, int min_delay, int max_delay, int rate, int wrap)
{
    if (n <= 0) return;
    const uint64_t turn = (uint64_t)1 << 32;
    const uint32_t q_step = (uint32_t)(turn / (uint32_t)n), r_step = (uint32_t)(turn % (uint32_t)n);
    /* value = ((u * (max - min) + min) * 256 * rate / 10000) with u = (sin + 1) / 2 in Q20:
     * N = u20 * (max - min) + (min << 20) (< 2^29 for Uint8 delays), value = N * K >> 32 */
    const uint64_t k = ((uint64_t)256 * (uint64_t)rate << 32) / ((uint64_t)10000 << 20);
    const int span = max_delay - min_delay;
    uint32_t q = 0, r = 0;
    for (int i = 0; i < n; i++) {
        uint32_t idx = q >> 22, frac = (q >> 6) & 0xFFFF;
        int32_t a = kestrel_sine_q30[idx], b = kestrel_sine_q30[idx + 1];
        int32_t s = a + (((b - a) >> 8) * (int32_t)frac >> 8);   /* |b - a| < 2^23: the product fits 32 bits */
        int32_t u20 = (int32_t)(((uint32_t)s + (1u << 30)) >> 11);  /* (sin + 1) / 2 in Q20 */
        uint32_t num = (uint32_t)(u20 * span + (min_delay << 20));   /* >= 0, < 2^29 */
        int32_t v = (int32_t)(((uint64_t)num * k) >> 32);
        lut[i] = v < wrap ? v : wrap > 0 ? v % wrap : v;   /* Uint8 delays (< 25.6 ms) stay below the 50 ms wrap */
        q += q_step; r += r_step;
        if (r >= (uint32_t)n) { r -= (uint32_t)n; q++; }
    }
}
