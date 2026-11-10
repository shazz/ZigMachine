// ASTRO BENCH's batch jobs: LINPACK 100 (netlib's dgefa + dgesl, rolled, n = 100, lda = 201)
// in the cart's own f64 and as two ASTROLABE descriptors; and sin() over 4096 elements in the
// cart's f64, its f32, and one ASTROLABE MAP (f64 out, then f32 out). The cart's dgefa/dgesl
// are the same operations in the same order as machine/astro_linpack.zig: same bits.
#ifndef ASTRO_JOBS_BATCH_H
#define ASTRO_JOBS_BATCH_H

#include "../../zigmachine_mem.h"

enum { LN = 100, LDA = 201, NSIN = 4096 };

static void daxpy(int n, double da, const double* dx, double* dy) {
    if (n <= 0 || da == 0) return;
    for (int i = 0; i < n; i++) dy[i] = dy[i] + da * dx[i];
}
static int idamax(int n, const double* dx) {
    if (n <= 1) return 0;
    double dmax = __builtin_fabs(dx[0]);
    int best = 0;
    for (int i = 1; i < n; i++) if (__builtin_fabs(dx[i]) > dmax) best = i, dmax = __builtin_fabs(dx[i]);
    return best;
}
static void dgefa(double* a, int lda, int n, int* ipvt) {
    for (int k = 0; k < n - 1; k++) {
        double* col = &a[lda * k];
        int l = idamax(n - k, &col[k]) + k;
        ipvt[k] = l;
        if (col[l] == 0) continue;
        if (l != k) { double t = col[l]; col[l] = col[k], col[k] = t; }
        double t = -1.0 / col[k];
        for (int i = k + 1; i < n; i++) col[i] = t * col[i];
        for (int j = k + 1; j < n; j++) {
            double* cj = &a[lda * j];
            double tj = cj[l];
            if (l != k) cj[l] = cj[k], cj[k] = tj;
            daxpy(n - (k + 1), tj, &col[k + 1], &cj[k + 1]);
        }
    }
    ipvt[n - 1] = n - 1;
}
static void dgesl(const double* a, int lda, int n, const int* ipvt, double* b) {
    for (int k = 0; k < n - 1; k++) {
        int l = ipvt[k];
        double t = b[l];
        if (l != k) b[l] = b[k], b[k] = t;
        daxpy(n - (k + 1), t, &a[lda * k + k + 1], &b[k + 1]);
    }
    for (int kb = 0; kb < n; kb++) {
        int k = n - 1 - kb;
        b[k] = b[k] / a[lda * k + k];
        daxpy(k, -b[k], &a[lda * k], &b[0]);
    }
}
static void matgen(double* a, double* b) {
    int init = 1325;
    for (int j = 0; j < LN; j++) for (int i = 0; i < LN; i++) init = 3125 * init % 65536, a[LDA * j + i] = (init - 32768.0) / 16384.0;
    for (int i = 0; i < LN; i++) { b[i] = 0; for (int j = 0; j < LN; j++) b[i] += a[LDA * j + i]; }
}
static double resid(const double* x) {
    double w = 0;
    for (int i = 0; i < LN; i++) { double d = __builtin_fabs(x[i] - 1); w = d > w ? d : w; }
    return w;
}
static unsigned kflops(unsigned us) { return us ? (unsigned)(686667ull * 1000u / us) : 0; }

static void job_linpack(void) {
    zm_mark mark = zm_mark_now();
    double *a1 = zm_alloc(LDA * LN * 8, 8), *a2 = zm_alloc(LDA * LN * 8, 8), *b1 = zm_alloc(LN * 8, 8), *b2 = zm_alloc(LN * 8, 8);
    int *p1 = zm_alloc(LN * 4, 4), *p2 = zm_alloc(LN * 4, 4);
    if (!a1 || !a2 || !b1 || !b2 || !p1 || !p2) { chk(0, "linpack: out of memory"); zm_release(mark); return; }
    matgen(a1, b1), matgen(a2, b2);
    u32 t0 = hostMicros();
    dgefa(a1, LDA, LN, p1), dgesl(a1, LDA, LN, p1, b1);
    u32 t1 = hostMicros();
    ds[0] = (astro_desc){.op = AS_GEFA, .n = LN, .lda = LDA, .a = as_addr(a2), .b = as_addr(p2)};
    ds[1] = (astro_desc){.op = AS_GESL, .n = LN, .lda = LDA, .a = as_addr(a2), .b = as_addr(p2), .c = as_addr(b2)};
    chk(run(2) == 0 && ds[0].r == 0, "linpack: astro");
    u32 t2 = hostMicros();
    int same = 1;
    for (int i = 0; i < LN; i++) same &= as_bits(b1[i]) == as_bits(b2[i]);
    chk(resid(b1) < 1e-9 && resid(b2) < 1e-9, "linpack: residual");
    chk(same, "linpack: astro != soft");
    fm_reset(), fm_s("ZM ASTRO linpack kflops soft=");
    if (clocked) fm_u(kflops(t1 - t0)), fm_s(" astro="), fm_u(kflops(t2 - t1)); else fm_s("- astro=-");
    fm_s(" resid_e15="), fm_u((u64)(resid(b2) * 1e15)), fm_s(same ? " same" : " DIFFER"), say();
    zm_release(mark);
}

static void job_sin_batch(void) {
    zm_mark mark = zm_mark_now();
    double *x = zm_alloc(NSIN * 8, 8), *y1 = zm_alloc(NSIN * 8, 8), *y2 = zm_alloc(NSIN * 8, 8);
    float *y3 = zm_alloc(NSIN * 4, 4), *y4 = zm_alloc(NSIN * 4, 4);
    if (!x || !y1 || !y2 || !y3 || !y4) { chk(0, "sin batch: out of memory"); zm_release(mark); return; }
    for (int i = 0; i < NSIN; i++) x[i] = -3.0 + i * (6.0 / NSIN);
    u32 t0 = hostMicros();
    for (int i = 0; i < NSIN; i++) y1[i] = sin(x[i]);
    u32 t1 = hostMicros();
    for (int i = 0; i < NSIN; i++) y3[i] = sinf((float)x[i]);
    u32 t2 = hostMicros();
    ds[0] = (astro_desc){.op = AS_MAP, .n = NSIN, .m = AS_FN_SIN, .a = as_addr(x), .c = as_addr(y2)};
    chk(run(1) == 0, "sin batch: astro");
    u32 t3 = hostMicros();
    ds[0] = (astro_desc){.op = AS_MAP | AS_F32_OUT, .n = NSIN, .m = AS_FN_SIN, .a = as_addr(x), .c = as_addr(y4)};
    chk(run(1) == 0, "sin batch: astro f32");
    u64 ulp = 0;
    double err32 = 0;
    int same32 = 1;
    for (int i = 0; i < NSIN; i++) {
        u64 d = as_ulp(y1[i], y2[i]);
        ulp = d > ulp ? d : ulp;
        double e = __builtin_fabs((double)y3[i] - y1[i]);
        err32 = e > err32 ? e : err32;
        same32 &= y4[i] == (float)y1[i];
    }
    chk(ulp == 0, "sin batch: astro != soft");
    chk(same32, "sin batch: astro f32 != (float)sin");
    chk(err32 < 1e-6, "sin batch: f32 error");
    fm_reset(), fm_s("ZM ASTRO sin4096"), fm_ns("soft64", t1 - t0, NSIN, clocked), fm_ns("f32", t2 - t1, NSIN, clocked);
    fm_ns("astro", t3 - t2, NSIN, clocked), fm_s(" ulp="), fm_u(ulp), fm_s(" f32_err_e9="), fm_u((u64)(err32 * 1e9)), say();
    zm_release(mark);
}

#endif
