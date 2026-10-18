/* The stale-line case on the board's cart core (tests/test_blit_dcache.py, tests/tb/dcache_tb.cpp):
 * for each op, the CPU caches the destination's old pixels, the harness's stand-in for CHISEL
 * rewrites the op's box in RAM behind the cache, then bblit.c's step 4 runs, and the CPU reads
 * the box back. MODE 0: no invalidate (must read stale pixels, else the case proves nothing);
 * 1: cycles/bdinval.h, as bblit.c (must read the new ones and keep an unrelated line cached);
 * 2: the whole-cache invalidate, the old step 4. Exit 0, or 10 + the first case that read stale.
 * REPORT tag * 1000000 + value: 1/2 cycles of case 1/2's step 4 (cold I-cache), 6/7 the same
 * again (warm, as on the board after the first blit), 8 a 16x16 tile's (warm), 3 a whole-cache
 * invalidate, 4 refills of the unrelated line, 5 a 128-line range, 9 the cases that fell back to
 * the whole cache (bit n = case n). */
#include <stdint.h>

#include "bdinval.h"

/* vboard.h's, without the SoC's CSR headers it pulls in. */
static inline void zmv_flush_dcache(void) { __asm__ volatile(".word(0x500F)\n" ::: "memory"); }

#define DEV ((volatile uint32_t*)0xf0000000u)
#define REGION ((volatile uint8_t*)0x40100000u) /* the video region: registers, then pixels */
#define D_BASE 0x1100u                            /* OFF_VRAM */
#ifndef MODE
#define MODE 1
#endif

typedef struct {
    uint8_t cmd, con;
    uint16_t stride;
    int16_t x[3], y[3];
    uint16_t w, h, clip[4];
    uint16_t ex, ey, ew, eh; /* the clipped box: what the stand-in writes */
} op_t;

static const op_t OPS[] = {
    {ZM_BLIT_CMD_FILL, 0, 320, {5}, {3}, 37, 9, {0}, 5, 3, 37, 9},          /* row by row */
    {ZM_BLIT_CMD_FILL, 0, 320, {0}, {10}, 320, 4, {0}, 0, 10, 320, 4},      /* one span */
    {ZM_BLIT_CMD_BLIT, ZM_CON_CLIP_EN, 320, {-10}, {-5}, 100, 50, {2, 2, 30, 20}, 2, 2, 30, 20},
    {ZM_BLIT_CMD_FILL, 0, 400, {390}, {270}, 20, 20, {0}, 390, 270, 10, 10}, /* fullscreen plane edge */
    {ZM_BLIT_CMD_LINE, 0, 320, {10, 60}, {150, 140}, 0, 0, {0}, 10, 140, 51, 11},
    {ZM_BLIT_CMD_TRIANGLE, 0, 320, {100, 140, 90}, {100, 120, 130}, 0, 0, {0}, 90, 100, 51, 31},
    {ZM_BLIT_CMD_BLIT, 0, 320, {48}, {64}, 16, 16, {0}, 48, 64, 16, 16},  /* a tile, line-aligned */
    {ZM_BLIT_CMD_BLIT, 0, 320, {203}, {91}, 16, 16, {0}, 203, 91, 16, 16}, /* a tile across lines */
    {ZM_BLIT_CMD_FILL, 0, 320, {0}, {0}, 320, 200, {0}, 0, 0, 320, 200},  /* a clear: whole cache */
};
#define NOPS (sizeof OPS / sizeof OPS[0])

static volatile uint32_t desc[5];
static volatile uint32_t sink;

static void report(uint32_t tag, uint32_t v) { DEV[2] = tag * 1000000u + v; }
static volatile uint8_t* px(const op_t* o, uint32_t x, uint32_t y) { return REGION + D_BASE + y * o->stride + x; }

static void w16(uint32_t off, uint16_t v) { *(volatile uint16_t*)(REGION + off) = v; }

static void set_regs(const op_t* o) {
    REGION[ZM_BLIT_COMMAND] = o->cmd;
    REGION[ZM_BLIT_CON] = o->con;
    *(volatile uint32_t*)(REGION + ZM_BLIT_D_BASE) = D_BASE;
    w16(ZM_BLIT_D_STRIDE, o->stride);
    w16(ZM_BLIT_W, o->w);
    w16(ZM_BLIT_H, o->h);
    for (int k = 0; k < 3; k++) w16(ZM_BLIT_X0 + 4u * k, (uint16_t)o->x[k]), w16(ZM_BLIT_Y0 + 4u * k, (uint16_t)o->y[k]);
    for (int k = 0; k < 4; k++) w16(ZM_BLIT_CLIP_X + 2u * k, o->clip[k]);
}

static uint32_t fell_back; /* bit n: case n took the whole-cache invalidate */

static void step4(uint32_t n, const volatile uint8_t* r, uint8_t cmd) {
#if MODE == 1
    if (!bdi_range(r, cmd)) bdi_inval_all(), fell_back |= 1u << n;
#elif MODE == 2
    zmv_flush_dcache();
#else
    (void)n, (void)r, (void)cmd;
#endif
}

static uint32_t probes(const op_t* o, volatile uint8_t* p[5]) {
    uint32_t x1 = o->ex + o->ew - 1u, y1 = o->ey + o->eh - 1u;
    p[0] = px(o, o->ex, o->ey), p[1] = px(o, x1, o->ey), p[2] = px(o, o->ex, y1), p[3] = px(o, x1, y1);
    p[4] = px(o, o->ex + o->ew / 2u, o->ey + o->eh / 2u);
    return 5;
}

/* 1 when the box read back stale after step 4. */
static int run_case(uint32_t n, const op_t* o) {
    volatile uint8_t* p[5];
    uint8_t color = (uint8_t)(0xC0 + n);
    set_regs(o);
    for (uint32_t j = 0; j < o->eh; j++)
        for (uint32_t i = 0; i < o->ew; i++) *px(o, o->ex + i, o->ey + j) = 0x11;
    uint32_t np = probes(o, p);
    for (uint32_t k = 0; k < np; k++) sink = *p[k]; /* the old pixels, now in the D-cache */
    /* An unrelated line on an index case 1 cannot touch (row 3's gap, 4 KiB-aliased away). */
    volatile uint8_t* other = (volatile uint8_t*)(((uintptr_t)px(o, 165, 3) & ~31u) + 0x100000u);
    sink = *other;
    DEV[4] = (uint32_t)(uintptr_t)other;
    desc[0] = (uint32_t)(uintptr_t)px(o, o->ex, o->ey), desc[1] = o->stride, desc[2] = o->ew, desc[3] = o->eh;
    desc[4] = color;
    DEV[3] = (uint32_t)(uintptr_t)desc; /* CHISEL: the box rewritten in RAM, behind the cache */
    uint32_t t = DEV[1];
    step4(n, REGION, o->cmd);
    t = DEV[1] - t;
    if (n < 2) report(n + 1, t);
    if (n < 2 || n == 6) { /* again, warm: what step 4 costs on the board from the second blit on */
        uint32_t t2 = DEV[1];
        step4(n, REGION, o->cmd);
        report(n == 6 ? 8 : n + 6, DEV[1] - t2);
    }
    int stale = 0;
    for (uint32_t k = 0; k < np; k++) stale |= *p[k] != color;
    sink = *other;
    if (n == 0) report(4, DEV[5]);
    return stale;
}

int main(void) {
    int bad = 0;
    for (uint32_t n = 0; n < NOPS; n++)
        if (run_case(n, &OPS[n]) && !bad) bad = 10 + (int)n;
    uint32_t t = DEV[1];
    zmv_flush_dcache();
    report(3, DEV[1] - t);
    t = DEV[1];
    bdi_span(0x40200000u, 0x40200000u + 128u * BDI_LINE);
    report(5, DEV[1] - t);
    report(9, fell_back);
    return bad;
}
