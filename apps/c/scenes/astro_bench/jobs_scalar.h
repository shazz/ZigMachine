// ASTRO BENCH's latency and scalar jobs. Each op four ways: one ASTROLABE call per op (the
// round trip), 48 ops a call (the batch), the cart's own f64 (soft-float on the board's ZIGGY)
// and its f32 (the FPU when the bitstream's core has one). Every ASTROLABE result is checked
// against the cart's own f64: IEEE ops and compiler_rt's sin must agree to the bit.
#ifndef ASTRO_JOBS_SCALAR_H
#define ASTRO_JOBS_SCALAR_H

double sin(double);
float sinf(float);

static astro_desc ds[AS_MAX] __attribute__((aligned(8)));
static volatile double sink;
static volatile float sinkf;
static int clocked, failures;
static unsigned served, calls;

static void say(void);
static void chk(int ok, const char* what) {
    if (ok) return;
    failures++;
    fm_reset(), fm_s("ZM ASTRO FAIL "), fm_s(what), say();
}

static double soft(u32 op, double a, double b) {
    switch (op) {
    case AS_ADD: return a + b;
    case AS_MUL: return a * b;
    case AS_DIV: return a / b;
    case AS_SQRT: return __builtin_sqrt(a);
    default: return sin(a);
    }
}
static float softf(u32 op, float a, float b) {
    switch (op) {
    case AS_ADD: return a + b;
    case AS_MUL: return a * b;
    case AS_DIV: return a / b;
    case AS_SQRT: return __builtin_sqrtf(a);
    default: return sinf(a);
    }
}
static double in_a(unsigned i) { return 0.37 + i * 0.731; }
static double in_b(unsigned i) { return 1.13 + i * 0.19; }

static u32 run(u32 count) {
    u32 st = hwAstro(as_addr(ds), count);
    calls++;
    served += (ds[0].status & AS_SERVED_ARM) != 0;
    return st;
}

// the round trip: NOP calls, ZIGGY's cycles of each (W_CYCLES, the board's only) min / median / max
static void job_roundtrip(void) {
    enum { N = 256 };
    static u32 cyc[N];
    u32 t0 = hostMicros();
    for (int i = 0; i < N; i++) as_scalar(&ds[0], AS_NOP, 0, 0), chk(run(1) == 0, "NOP"), cyc[i] = ds[0].cycles;
    u32 us = hostMicros() - t0;
    for (int i = 1; i < N; i++) for (int j = i; j > 0 && cyc[j - 1] > cyc[j]; j--) { u32 t = cyc[j]; cyc[j] = cyc[j - 1], cyc[j - 1] = t; }
    fm_reset(), fm_s("ZM ASTRO roundtrip"), fm_ns("ns", us, N, clocked);
    fm_s(" cycles="), fm_u(cyc[0]), fm_s("/"), fm_u(cyc[N / 2]), fm_s("/"), fm_u(cyc[N * 99 / 100]), fm_s("/"), fm_u(cyc[N - 1]);
    fm_s(" served="), fm_u(served), fm_s("/"), fm_u(calls), say();
}

static void job_scalar(u32 op, const char* name) {
    enum { N1 = 256, NB = 16, NS = 4096 };
    u32 t0 = hostMicros();
    for (int k = 0; k < N1; k++) as_scalar(&ds[0], op, in_a(k & 31), in_b(k & 31)), run(1), sink = ds[0].r;
    u32 t1 = hostMicros();
    for (int k = 0; k < NB; k++) {
        for (unsigned i = 0; i < AS_MAX; i++) as_scalar(&ds[i], op, in_a(i), in_b(i));
        run(AS_MAX);
    }
    u32 t2 = hostMicros();
    double acc = 0;
    for (int i = 0; i < NS; i++) acc += soft(op, in_a(i & 31) + i * 1e-7, in_b(i & 31));
    sink = acc;
    u32 t3 = hostMicros();
    float accf = 0;
    for (int i = 0; i < NS; i++) accf += softf(op, (float)in_a(i & 31) + i * 1e-7f, (float)in_b(i & 31));
    sinkf = accf;
    u32 t4 = hostMicros();
    u64 worst = 0;
    for (unsigned i = 0; i < AS_MAX; i++) {
        u64 d = as_ulp(ds[i].r, soft(op, in_a(i), in_b(i)));
        worst = d > worst ? d : worst;
        chk((ds[i].status & 0xFF) == 0, name);
    }
    chk(worst == 0, name);
    fm_reset(), fm_s("ZM ASTRO "), fm_s(name), fm_ns("astro1", t1 - t0, N1, clocked), fm_ns("astro48", t2 - t1, NB * AS_MAX, clocked);
    fm_ns("soft64", t3 - t2, NS, clocked), fm_ns("f32", t4 - t3, NS, clocked), fm_s(" ulp="), fm_u(worst), say();
}

// a few results as bits, for the harness to hold against its own (JavaScript's) arithmetic
static void job_reference(void) {
    as_scalar(&ds[0], AS_SIN, 0.5, 0), as_scalar(&ds[1], AS_DIV, 1, 3), as_scalar(&ds[2], AS_SQRT, 2, 0);
    as_scalar(&ds[3], AS_EXP, 1, 0), as_scalar(&ds[4], AS_POW, 2, 0.5), as_scalar(&ds[5], AS_ATAN2, 1, -1);
    ds[6] = (astro_desc){.op = AS_FMA, .s0 = 1.0 + 1.0 / (1 << 30), .s1 = 1.0 + 1.0 / (1 << 30), .s2 = -1.0 - 2.0 / (1 << 30)};
    chk(run(7) == 0, "reference");
    fm_reset(), fm_s("ZM ASTRO ref");
    for (int i = 0; i < 7; i++) fm_s(" "), fm_x(as_bits(ds[i].r));
    say();
}

#endif
