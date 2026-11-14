// ASTRO BENCH's effect page: a Julia set (c = -0.123 + 0.745i, "the rabbit") zoomed 1e12 deep into its
// repelling fixed point, every pixel's maths done in f64 by ASTROLABE, with ZIGGY's own soft f64 one
// key away (SPACE) so the difference is something you SEE and read off (ms a picture, pictures a second).
//
// Per-frame float is allowed here, and only here, because ASTROLABE is the point: the A side is the
// comparison (the same maths as a cart would write it: ZIGGY's soft-float, ~100 cycles an op). The B
// side never touches an FPU op: it hands descriptors over; ZIGGY moves bits and scans the escaped
// cells with INTEGER ops on the f64 words (exponent >= 1024 = |re| or |im| >= 2), as COPRO page 5 does.
// What differs from COPRO page 5 (a Mandelbrot at 64 x 35 cells): a Julia set at 80 x 40 cells, every
// zoom step a whole picture in one frame (40 iterations x 7 vector ops over 3200 cells), a live A/B
// that gives the SAME pixels both ways (the hash logged every 8 steps proves it) and a rate readout.
#ifndef ASTRO_ZOOM_H
#define ASTRO_ZOOM_H

#include "../../zigmachine_mem.h"

ROM_IMPORT("hwVideoBase") extern int hwVideoBase(void);

enum { ZW = 80, ZH = 40, ZP = ZW * ZH, ZCELL = 4, ZITER = 4, ZROUNDS = 10, ZSTEPS = 420, ZPAL = 16, ZPER = 7 * ZITER };
#define OFF_PAL 0x100
#define OFF_VRAM 0x1100
#define JC_R (-0.123)
#define JC_I 0.745

static double *zr, *zi, *cr, *ci, *t0, *t1, *t2, *ix, *iy, *ones, *tx, *ty, *td;
static unsigned short* al; // the cells still iterating
static unsigned na;
static astro_desc zset[6] __attribute__((aligned(8))), zits[ZPER] __attribute__((aligned(8)));
static int zok, zsoft, zstep, zround, zit, zarm;
static u32 zhash, zcalc_us, zwin_us, zwin_imgs, zlast_us, zfail;
static u32 zimg_us; // the picture being computed: ZIGGY's time so far
static u32 hud_us, hud_ms10, hud_ips10;

static unsigned char* vram(void) { return (unsigned char*)(hwVideoBase() + OFF_VRAM); }
static u32 hiw(const double* p) { return ((const u32*)p)[1]; } // sign, exponent, top mantissa: no FPU op

static astro_desc dsc(u32 op, const double* a, const double* b, double* c) {
    return (astro_desc){.op = op, .n = ZP, .a = as_addr(a), .b = as_addr(b), .c = as_addr(c)};
}

static void zoom_palette(void) {
    unsigned char* p = (unsigned char*)(hwVideoBase() + OFF_PAL);
    for (int i = 0; i < ZPAL; i++) {
        int t = i < 8 ? i : 15 - i; // a triangle wave: a loop of colour bands
        unsigned char* e = p + (ZPAL + i) * 4;
        e[0] = (unsigned char)(24 + t * 30), e[1] = (unsigned char)(8 + t * t * 4), e[2] = (unsigned char)(120 + t * 16), e[3] = 255;
    }
}

// the iteration z = z^2 + c as 7 vector ops, ZITER times: the same descriptors every round
static void zoom_build(void) {
    for (int k = 0; k < ZITER; k++) {
        astro_desc* d = &zits[7 * k];
        d[0] = dsc(AS_VMUL, zr, zr, t0), d[1] = dsc(AS_VMUL, zi, zi, t1), d[2] = dsc(AS_VMUL, zr, zi, t2);
        d[3] = dsc(AS_AXPY, t1, t0, 0), d[3].s0 = -1.0; // t0 = -1 * t1 + t0
        d[4] = dsc(AS_VADD, t0, cr, zr), d[5] = dsc(AS_VADD, t2, t2, zi), d[6] = dsc(AS_VADD, zi, ci, zi);
    }
    zset[0] = dsc(AS_SCAL, ones, 0, zr), zset[1] = dsc(AS_AXPY, ix, zr, 0), zset[2] = dsc(AS_SCAL, ones, 0, zi);
    zset[3] = dsc(AS_AXPY, iy, zi, 0), zset[4] = dsc(AS_SCAL, ones, 0, cr), zset[5] = dsc(AS_SCAL, ones, 0, ci);
    zset[4].s0 = JC_R, zset[5].s0 = JC_I;
}

// the tables (init: float is fine, built once): the view of every step, centred on the fixed point (1 + sqrt(1 - 4c)) / 2
static void zoom_init(void) {
    double** all[] = {&zr, &zi, &cr, &ci, &t0, &t1, &t2, &ix, &iy, &ones};
    for (unsigned k = 0; k < sizeof all / sizeof all[0]; k++) if (!(*all[k] = zm_alloc(ZP * 8, 8))) return;
    tx = zm_alloc(ZSTEPS * 8, 8), ty = zm_alloc(ZSTEPS * 8, 8), td = zm_alloc(ZSTEPS * 8, 8), al = zm_alloc(ZP * 2, 2);
    if (!tx || !ty || !td || !al) return;
    for (int i = 0; i < ZP; i++) ix[i] = (double)(i % ZW), iy[i] = (double)(i / ZW), ones[i] = 1.0;
    double wr = 1.0 - 4.0 * JC_R, wi = -4.0 * JC_I, m = __builtin_sqrt(wr * wr + wi * wi);
    double zx = (1.0 + __builtin_sqrt((m + wr) / 2.0)) / 2.0, zy = -__builtin_sqrt((m - wr) / 2.0) / 2.0, dx = 4.0 / ZW;
    for (int k = 0; k < ZSTEPS; k++) td[k] = dx, tx[k] = zx - dx * (ZW / 2), ty[k] = zy - dx * (ZH / 2), dx *= 0.9375;
    zoom_build(), zoom_palette();
    zok = 1;
}

static void paint(unsigned i, unsigned v) {
    unsigned char* p = vram() + (i / ZW) * ZCELL * 320 + (i % ZW) * ZCELL;
    for (int y = 0; y < ZCELL; y++) *(u32*)(p + y * 320) = v * 0x01010101u;
}

static u32 zrun(astro_desc* l, u32 n) {
    u32 st = hwAstro(as_addr(l), n);
    zarm = (l[0].status & AS_SERVED_ARM) != 0;
    if (st) zfail++;
    return st;
}

static void zimage_begin(void) {
    zhash = 0, zit = 0, na = ZP;
    for (unsigned i = 0; i < ZP; i++) al[i] = (unsigned short)i;
    u64 bits[3] = {as_bits(0), as_bits(0), as_bits(0)};
    __builtin_memcpy(&bits[0], &tx[zstep], 8), __builtin_memcpy(&bits[1], &ty[zstep], 8), __builtin_memcpy(&bits[2], &td[zstep], 8);
    if (!zsoft) { // x = x0 * 1 + dx * ix, the same for y, c broadcast: 6 descriptors, no float op on ZIGGY
        __builtin_memcpy(&zset[0].s0, &bits[0], 8), __builtin_memcpy(&zset[1].s0, &bits[2], 8);
        __builtin_memcpy(&zset[2].s0, &bits[1], 8), __builtin_memcpy(&zset[3].s0, &bits[2], 8);
        zrun(zset, 6);
        return;
    }
    for (unsigned i = 0; i < ZP; i++) zr[i] = ix[i] * td[zstep] + tx[zstep], zi[i] = iy[i] * td[zstep] + ty[zstep];
}

// ZIGGY's own f64: the same z^2 + c, ZITER times, cell by cell
static void soft_round(void) {
    for (unsigned k = 0; k < na; k++) {
        unsigned i = al[k];
        double re = zr[i], im = zi[i];
        for (int n = 0; n < ZITER; n++) {
            double a = re * re, b = im * im, c = re * im;
            re = (a - b) + JC_R, im = (c + c) + JC_I;
        }
        zr[i] = re, zi[i] = im;
    }
}

// escaped cells: coloured and (on ASTROLABE) frozen at 0; integer ops on the f64 words only
static void scan(void) {
    unsigned n2 = 0;
    for (unsigned k = 0; k < na; k++) {
        unsigned i = al[k], e = ((hiw(&zr[i]) >> 20) & 0x7FF), e2 = (hiw(&zi[i]) >> 20) & 0x7FF;
        e = e > e2 ? e : e2;
        if (e < 1024) { al[n2++] = (unsigned short)i; continue; }
        unsigned lg = 31 - (unsigned)__builtin_clz(e - 1022), col = ((unsigned)zit * 2 - lg * 2) & 15;
        paint(i, ZPAL + col);
        zhash = (zhash * 33u) ^ (i << 8 | col);
        if (!zsoft) ((u64*)zr)[i] = 0, ((u64*)zi)[i] = 0, ((u64*)cr)[i] = 0, ((u64*)ci)[i] = 0;
    }
    na = n2;
}

static void zimage_end(void) {
    for (unsigned k = 0; k < na; k++) paint(al[k], BLACK);
    fm_reset(), fm_s("ZM ASTRO zoom step="), fm_u((unsigned)zstep), fm_s(zsoft ? " side=ziggy" : " side=astro"), fm_s(" hash="), fm_u(zhash);
    if ((zstep & 7) == 0) consoleLogJS(fm_buf, (int)fm_len);
    zwin_imgs++, zstep = (zstep + 1) % ZSTEPS, zround = 0;
}

static void zoom_hud(void);
static void zoom_tick(void) {
    if (!zok) return;
    u32 t = hostMicros();
    if (zround == 0) zimage_begin();
    for (int r = 0, n = zsoft ? 1 : ZROUNDS; r < n && zround < ZROUNDS && na; r++, zround++) {
        if (zsoft) soft_round(); else zrun(zits, ZPER);
        zit += ZITER, scan();
    }
    if (zround >= ZROUNDS || !na) zimage_end();
    zcalc_us += hostMicros() - t;
    zoom_hud();
}

static void zoom_start(int soft) {
    zsoft = soft, zround = 0, zwin_imgs = zcalc_us = 0, zwin_us = hostMicros(), hud_us = 0;
    if (!zok) return;
    if (gui) guiRect(gui, 0, ZH * ZCELL, 320, 200 - ZH * ZCELL, WHITE);
    hud_ms10 = hud_ips10 = 0;
}

static void hud_row(int r, const char* s) {
    if (gui) guiRect(gui, 0, ZH * ZCELL + r * 10, 320, 10, WHITE), guiText(gui, s, fm_strlen(s) > COLS ? COLS : fm_strlen(s), 2, ZH * ZCELL + r * 10 + 2, BLACK, WHITE);
}

// the readout, redrawn twice a second (and on a switch): ms a picture and pictures a second, from the host clock
static void zoom_hud(void) {
    u32 now = hostMicros();
    int fresh = hud_us == 0;
    if (!fresh && (!clocked || now - zwin_us < 500000u)) return;
    if (clocked && zwin_imgs) hud_ms10 = zcalc_us / 100 / zwin_imgs, hud_ips10 = (u32)((unsigned long long)zwin_imgs * 10000000ull / (now - zwin_us));
    hud_us = now | 1, zwin_us = now, zwin_imgs = zcalc_us = 0;
    fm_reset(), fm_s("JULIA c=-0.123+0.745i zoom step "), fm_u((unsigned)zstep), fm_s("/420"), hud_row(0, fm_buf);
    fm_reset(), fm_s(zsoft ? "NOW: ZIGGY soft f64    SPACE = ASTRO" : zarm ? "NOW: ASTROLABE (ARM)  SPACE = ZIGGY" : "NOW: ASTROLABE (host) SPACE = ZIGGY"), hud_row(1, fm_buf);
    fm_reset();
    if (!clocked) fm_s("no clock on this host: no times");
    else fm_u(hud_ms10 / 10), fm_s("."), fm_u(hud_ms10 % 10), fm_s(" ms a picture  "), fm_u(hud_ips10 / 10), fm_s("."), fm_u(hud_ips10 % 10), fm_s(" pictures/s");
    hud_row(2, fm_buf);
    fm_reset(), fm_s("0.9M f64 ops a picture. 1 = bench"), hud_row(3, fm_buf);
}

#endif
