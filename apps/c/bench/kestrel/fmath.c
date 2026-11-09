/* The math the benchmark cart's libm lacks. Own code, CC0.
 *   atan(double)                  compiler_rt has no atan
 *   bsinf bcosf batanf bexpf blogf  single-precision twins that use ONLY f32 operations, so the "single"
 *                                 builds of Whetstone and LINPACK never touch an f64 op (a stock sinf
 *                                 computes in double inside, which is soft-float on the board's ZIGGY).
 * Accuracy is ~1e-7 (float) and ~1e-15 (atan double): enough for a benchmark's checksum, not a libm. */
#include "bench.h"

#define PI_F 3.14159265f
#define HALF_PI_F 1.57079633f
#define TWO_PI_F 6.28318531f
#define INV_TWO_PI_F 0.15915494f

static float roundf_(float x) { return (float)(int)(x + (x < 0 ? -0.5f : 0.5f)); }

/* sin on [-pi/2, pi/2]: Taylor through x^11 (error < 1e-9 there) */
static float sin_core(float x) {
    float x2 = x * x;
    return x * (1.0f + x2 * (-1.0f / 6 + x2 * (1.0f / 120 + x2 * (-1.0f / 5040 + x2 * (1.0f / 362880 + x2 * (-1.0f / 39916800))))));
}

float bsinf(float x) {
    x -= roundf_(x * INV_TWO_PI_F) * TWO_PI_F;          /* [-pi, pi] */
    if (x > HALF_PI_F) x = PI_F - x; else if (x < -HALF_PI_F) x = -PI_F - x;
    return sin_core(x);
}
float bcosf(float x) { return bsinf(x + HALF_PI_F); }

/* atan on |x| <= tan(15 deg) by its series, then two identities bring any x there */
static float atan_small(float x) {
    float x2 = x * x;
    return x * (1.0f + x2 * (-1.0f / 3 + x2 * (1.0f / 5 + x2 * (-1.0f / 7 + x2 * (1.0f / 9 + x2 * (-1.0f / 11))))));
}
float batanf(float x) {
    float s = x < 0 ? -1.0f : 1.0f, a = x * s, r;
    int inv = a > 1.0f;
    if (inv) a = 1.0f / a;
    if (a > 0.26794919f) r = 0.52359878f + atan_small((a * 1.7320508f - 1.0f) / (a + 1.7320508f));
    else r = atan_small(a);
    return s * (inv ? HALF_PI_F - r : r);
}

/* exp: x = k ln2 + r, exp(r) by Taylor through r^6, 2^k assembled in the exponent bits */
float bexpf(float x) {
    if (x > 88.0f) x = 88.0f; else if (x < -87.0f) x = -87.0f;
    float k = roundf_(x * 1.44269504f), r = x - k * 0.693147181f;
    float p = 1.0f + r * (1.0f + r * (0.5f + r * (1.0f / 6 + r * (1.0f / 24 + r * (1.0f / 120 + r * (1.0f / 720))))));
    union { float f; u32 u; } s; s.u = (u32)((int)k + 127) << 23;
    return p * s.f;
}

/* log: x = m 2^e with m in [sqrt(.5), sqrt(2)), log m = 2 atanh(s), s = (m-1)/(m+1) */
float blogf(float x) {
    if (x <= 0.0f) return -87.0f;
    union { float f; u32 u; } v; v.f = x;
    int e = (int)(v.u >> 23) - 127;
    v.u = (v.u & 0x007fffffu) | 0x3f800000u;
    float m = v.f;
    if (m > 1.41421356f) { m *= 0.5f; e++; }
    float s = (m - 1.0f) / (m + 1.0f), s2 = s * s;
    float l = 2.0f * s * (1.0f + s2 * (1.0f / 3 + s2 * (1.0f / 5 + s2 * (1.0f / 7 + s2 * (1.0f / 9)))));
    return l + (float)e * 0.693147181f;
}

static double atan_small_d(double x) {
    double x2 = x * x, p = 0;
    for (int n = 29; n >= 1; n -= 2) p = p * x2 + (n & 2 ? -1.0 : 1.0) / n;  /* sum (-1)^k x^(2k) / (2k+1) */
    return x * p;
}
double atan(double x) {
    double s = x < 0 ? -1.0 : 1.0, a = x * s, r;
    int inv = a > 1.0;
    if (inv) a = 1.0 / a;
    if (a > 0.2679491924311227) r = 0.5235987755982988 + atan_small_d((a * 1.7320508075688772 - 1.0) / (a + 1.7320508075688772));
    else r = atan_small_d(a);
    return s * (inv ? 1.5707963267948966 - r : r);
}
