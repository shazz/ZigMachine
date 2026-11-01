/* Test 9: CHISEL's QUEUE (HW 1.11.0: memmap BLIT_CMD_QUEUE, cycles/bchisel.c, rtl/blitter/zm_blit_q.v).
 * The same small ops through one hwBlit each (sync: the call, the wrapper, CHISEL's start and
 * drain every op) and as descriptor lists (list: a header and the changed words into the ring,
 * one hwBlit per half-ring list, CHISEL running a list while the CPU builds the next, a NOP
 * hwBlit at the end that waits). As libs/zig/blit_queue.zig does it: a word goes in the ring only
 * when the list does not hold it yet. 64 8x8 and 16x16 fills and copies (cart RAM to VRAM), and
 * 256 one-row spans of varying width with ~140 cycles of ALU work between them, a stniccc
 * frame in miniature (its 1014 spans a frame). The 8x8 sync baselines are as.seq.f8.x64 and
 * as.seq.f8w.x64 (tests_async.c). bench_queue_calls() times a list's build + kick and its wait
 * apart: the CPU's own price, and what CHISEL had left. */
#include "bench.h"

#define TILES 0x10000u /* as tests_chisel.c: the small ops' corner */
#define STRIDE BENCH_BLIT_STRIDE
#define HALF (ZM_BLIT_QUEUE_WORDS / 2u)
#define SRC (BENCH_RAM_AT + 0x40000u) /* cart RAM, a linear address: the copies' source */
#define DEST (BENCH_BLIT_OFF + TILES)

static uint32_t q_first, q_n; /* .bss: a lean cart has no .data */

static volatile uint32_t* ring(void) { return (volatile uint32_t*)(g.vreg + ZM_OFF_BLIT_QUEUE); }

static void q_kick(void) {
    if (!q_n) return;
    *(volatile uint32_t*)(g.vreg + ZM_BLIT_Q_START) = q_first | q_n << 16;
    g.vreg[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_QUEUE;
    chisel_hwblit();
    q_first = HALF - q_first, q_n = 0;
}

static void q_flush(void) {
    q_kick();
    chisel_sync();
}

/* Room for `n` words, and a new list opens with the destination (the queue's own words, as
 * blit_list.zig restates them: here always, D_BASE and D_STRIDE). */
static volatile uint32_t* q_room(uint32_t n) {
    if (q_n + 3u + n > HALF) q_kick();
    volatile uint32_t* p = ring() + q_first + q_n;
    if (q_n == 0) {
        p[0] = 1u << 8 | 1u << 9, p[1] = DEST, p[2] = STRIDE;
        p += 3, q_n = 3;
    }
    q_n += n;
    return p;
}

/* As blit_queue.zig's fill: a header and three words, stored as given. */
static void q_fill(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    volatile uint32_t* p = q_room(4);
    p[0] = (uint32_t)ZM_BLIT_CMD_FILL << 24 | 1u << 1 | 1u << 10 | 1u << 11;
    p[1] = 0x5A, p[2] = w | h << 16, p[3] = x | y << 16;
}

/* As chisel_copy.zig's queueRect: a header and every word the BLIT needs. */
static void q_copy(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    volatile uint32_t* p = q_room(7);
    p[0] = (uint32_t)ZM_BLIT_CMD_BLIT << 24 | 1u << 0 | 1u << 1 | 1u << 4 | 1u << 5 | 1u << 10 | 1u << 11;
    p[1] = ZM_MT_B << 8 | ZM_CON_USEB << 16, p[2] = (uint32_t)ZM_CON2_SRC_ABS << 24, p[3] = SRC, p[4] = STRIDE;
    p[5] = w | h << 16, p[6] = x | y << 16;
}

static void prep(const bench_case* c) { /* the block: CON, CON2 and the halftone cleared, as a cart leaves them */
    (void)c;
    chisel_fill(DEST, STRIDE, 8, 8);
    q_first = 0, q_n = 0;
}

/* size: the side (8 or 16); arg bit 0: copies; arg >> 1: ALU ops between. */
static void tile_xy(uint32_t side, uint32_t i, uint32_t* x, uint32_t* y) { /* side 8 or 16: no divide */
    uint32_t sh = side == 8u ? 3u : 4u, per = STRIDE >> sh;
    *x = (i & (per - 1u)) << sh, *y = (i >> (9u - sh)) << sh;
}
static void tiles_sync(const bench_case* c) {
    for (uint32_t i = 0, x, y; i < c->ops; i++) {
        tile_xy(c->size, i, &x, &y);
        if (c->arg & 1) chisel_copy(DEST + y * STRIDE + x, SRC, STRIDE, c->size, c->size);
        else chisel_fill(DEST + y * STRIDE + x, STRIDE, c->size, c->size);
        if (c->arg >> 1) bench_sink = k_alu(c->arg >> 1);
    }
}
static void tiles_list(const bench_case* c) {
    for (uint32_t i = 0, x, y; i < c->ops; i++) {
        tile_xy(c->size, i, &x, &y);
        if (c->arg & 1) q_copy(x, y, c->size, c->size);
        else q_fill(x, y, c->size, c->size);
        if (c->arg >> 1) bench_sink = k_alu(c->arg >> 1);
    }
    q_flush();
}

/* Span i: one row of 8..107 pixels, rows in turn, as a polygon filler walks them. */
static void span(uint32_t i, uint32_t* x, uint32_t* y, uint32_t* w) {
    *x = (i * 37u) % 300u, *y = i % 200u, *w = 8u + (i * 13u) % 100u;
}
static void spans_sync(const bench_case* c) {
    for (uint32_t i = 0, x, y, w; i < c->ops; i++) {
        span(i, &x, &y, &w);
        chisel_fill(DEST + y * STRIDE + x, STRIDE, w, 1);
        bench_sink = k_alu(c->arg);
    }
}
static void spans_list(const bench_case* c) {
    for (uint32_t i = 0, x, y, w; i < c->ops; i++) {
        span(i, &x, &y, &w);
        q_fill(x, y, w, 1);
        bench_sink = k_alu(c->arg);
    }
    q_flush();
}

#define FILLS(n) ((n) << 1)
#define COPIES(n) (((n) << 1) | 1u)
const bench_case bench_queue_cases[] = {
    {"qu.list.f8.x64", tiles_list, prep, 8, 64, FILLS(0)},
    {"qu.list.f8w.x64", tiles_list, prep, 8, 64, FILLS(256)},
    {"qu.sync.f16.x64", tiles_sync, prep, 16, 64, FILLS(0)},
    {"qu.list.f16.x64", tiles_list, prep, 16, 64, FILLS(0)},
    {"qu.sync.c8.x64", tiles_sync, prep, 8, 64, COPIES(0)},
    {"qu.list.c8.x64", tiles_list, prep, 8, 64, COPIES(0)},
    {"qu.sync.c16.x64", tiles_sync, prep, 16, 64, COPIES(0)},
    {"qu.list.c16.x64", tiles_list, prep, 16, 64, COPIES(0)},
    {"qu.sync.span.256", spans_sync, prep, 0, 256, 100},
    {"qu.list.span.256", spans_list, prep, 0, 256, 100},
    {0, 0, 0, 0, 0, 0},
};

/* 64 8x8 fills as one list: the build and its kick (the CPU's price), then the wait. */
void bench_queue_calls(void) {
    uint32_t build[BENCH_REPEATS], wait[BENCH_REPEATS];
    for (int r = 0; r < BENCH_REPEATS; r++) {
        prep(0);
        uint32_t t0 = bench_cycles();
        for (uint32_t i = 0, x, y; i < 64; i++) tile_xy(8, i, &x, &y), q_fill(x, y, 8, 8);
        q_kick();
        uint32_t t1 = bench_cycles();
        chisel_sync();
        uint32_t t2 = bench_cycles();
        build[r] = t1 - t0, wait[r] = t2 - t1;
    }
    bench_record("qu.kick.f8.x64", 4096, 64, build, BENCH_REPEATS);
    bench_record("qu.wait.f8.x64", 4096, 64, wait, BENCH_REPEATS);
}
