// The zoom's third side: ZIGGY's f32 on the hardware FPU (the board's ZIGGY has one when built ZM_FPU=1;
// add/mul ~9-10 cycles, against ~100 for soft f64). Plain C `float`: the board build maps it to the FPU.
// Per-frame float is allowed here on purpose, as on the other two sides: the f32 side IS the comparison.
// Same maths as soft_round (z^2 + c, ZITER times a round, 1 round a frame, the same 40 iterations) and the
// same escape test (|re| or |im| >= 2, read off the exponent), so the A/B is fair.
//
// f32 has 24 bits (~7 digits): once the pixel step falls below f32's epsilon times the coordinate,
// neighbouring cells get the SAME f32 coordinate and the picture goes to blocks, then noise, while f64 stays
// sharp. Nothing is clamped: that is why f64 / ASTROLABE exist. zf32_break is the step where that happens.
#ifndef ASTRO_ZOOM_F32_H
#define ASTRO_ZOOM_F32_H

#define ZF32_EPS 1.1920929e-7 // 2^-23, f32's epsilon

static float *fzr, *fzi, *ftx, *fty, *ftd;
static unsigned zf32_break; // the first step whose pixel step is below ZF32_EPS * |coordinate|

static double zf32_abs(double v) { return v < 0 ? -v : v; }

static int zf32_init(const double* tx, const double* ty, const double* td, double cx, double cy) {
    fzr = zm_alloc(ZP * 4, 4), fzi = zm_alloc(ZP * 4, 4);
    ftx = zm_alloc(ZSTEPS * 4, 4), fty = zm_alloc(ZSTEPS * 4, 4), ftd = zm_alloc(ZSTEPS * 4, 4);
    if (!fzr || !fzi || !ftx || !fty || !ftd) return 0;
    double mag = zf32_abs(cx) > zf32_abs(cy) ? zf32_abs(cx) : zf32_abs(cy);
    zf32_break = ZSTEPS;
    for (int k = ZSTEPS - 1; k >= 0; k--) { // init only: tables built once from the f64 ones
        ftx[k] = (float)tx[k], fty[k] = (float)ty[k], ftd[k] = (float)td[k];
        if (td[k] < ZF32_EPS * mag) zf32_break = (unsigned)k;
    }
    return 1;
}

static void zf32_begin(int step) {
    float x0 = ftx[step], y0 = fty[step], d = ftd[step];
    for (unsigned i = 0; i < ZP; i++) fzr[i] = (float)(i % ZW) * d + x0, fzi[i] = (float)(i / ZW) * d + y0;
}

static void zf32_round(void) {
    const float cr32 = (float)JC_R, ci32 = (float)JC_I;
    for (unsigned k = 0; k < na; k++) {
        unsigned i = al[k];
        float re = fzr[i], im = fzi[i];
        for (int n = 0; n < ZITER; n++) {
            float a = re * re, b = im * im, c = re * im;
            re = (a - b) + cr32, im = (c + c) + ci32;
        }
        fzr[i] = re, fzi[i] = im;
    }
}

// the exponent of the larger of re, im as the f64 test reads it (f32's 8-bit field rebiased to 11 bits)
static unsigned zf32_exp(unsigned i) {
    unsigned e = (((const u32*)fzr)[i] >> 23) & 0xFF, e2 = (((const u32*)fzi)[i] >> 23) & 0xFF;
    return (e > e2 ? e : e2) + 896;
}

#endif
