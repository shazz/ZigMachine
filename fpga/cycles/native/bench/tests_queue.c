/* Test 9: CHISEL's QUEUE (HW 1.8.0: memmap BLIT_CMD_QUEUE, cycles/bchisel.c, rtl/blitter/zm_blit_q.v).
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

static uint32_t q_half, q_n, q_shadow[24], q_known, q_at, q_mask; /* .bss: a lean cart has no .data */

static volatile uint32_t* ring(void) { return (volatile uint32_t*)(g.vreg + ZM_OFF_BLIT_QUEUE); }
static void q_put(uint32_t v) { ring()[q_half * HALF + q_n++] = v; }

static void q_kick(void) {
    if (!q_n) return;
    *(volatile uint32_t*)(g.vreg + ZM_BLIT_Q_START) = q_half * HALF | q_n << 16;
    g.vreg[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_QUEUE;
    chisel_hwblit();
    q_half ^= 1u, q_n = 0, q_known = 0; /* the next list starts from the block: nothing known */
}

static void q_flush(void) {
    q_kick();
    chisel_sync();
}

/* A descriptor of up to `n` words: its header's place, the words the list does not hold yet
 * (rising k), then the header. */
static void q_begin(uint32_t n) {
    if (q_n + 1u + n > HALF) q_kick();
    q_at = q_n++, q_mask = 0;
}
static void q_word(uint32_t k, uint32_t v) {
    if ((q_known >> k & 1u) && q_shadow[k] == v) return;
    q_shadow[k] = v, q_known |= 1u << k, q_mask |= 1u << k;
    q_put(v);
}
static void q_end(uint32_t cmd) { ring()[q_half * HALF + q_at] = q_mask | cmd << 24; }

static void q_fill(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    q_begin(5);
    q_word(1, 0x5A); /* COLOR, CON2 0 */
    q_word(8, DEST), q_word(9, STRIDE);
    q_word(10, w | h << 16), q_word(11, x | y << 16);
    q_end(ZM_BLIT_CMD_FILL);
}

static void q_copy(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    q_begin(8);
    q_word(0, ZM_MT_B << 8 | ZM_CON_USEB << 16), q_word(1, (uint32_t)ZM_CON2_SRC_ABS << 24);
    q_word(4, SRC), q_word(5, STRIDE), q_word(8, DEST), q_word(9, STRIDE);
    q_word(10, w | h << 16), q_word(11, x | y << 16);
    q_end(ZM_BLIT_CMD_BLIT);
}

static void prep(const bench_case* c) { /* the block: CON, CON2 and the halftone cleared, as a cart leaves them */
    (void)c;
    chisel_fill(DEST, STRIDE, 8, 8);
    q_half = 0, q_n = 0, q_known = 0;
}

/* size: the side (8 or 16); arg bit 0: copies; arg >> 1: ALU ops between. */
static void tile_xy(uint32_t side, uint32_t i, uint32_t* x, uint32_t* y) {
    *x = (i % (STRIDE / side)) * side, *y = (i / (STRIDE / side)) * side;
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
