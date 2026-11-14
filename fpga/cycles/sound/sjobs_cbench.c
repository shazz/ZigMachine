/* BARD jobs' cost on BARD (zg.bard.job, table 1.24): the COPRO cart's four jobs, its sizes, through the
 * server BARD runs (libs/zig/bard_job_rv32.zig, built as cycles/sound.mk BJOB_ZIG), one job a timed "frame"
 * (cb_frame: cycles, bus waits, share of BARD's 60 Hz frame). The "cart memory" is a buffer in BARD's own
 * RAM, so this is the kernel and its DDR traffic, not ZIGGY's handover (a C2S store and a dflush).
 *   fpga/build/jobbench/dragon_zx0.h: xxd -i of `zx0pack tex_neoshow/dragon.raw` (the bench's caller makes it)
 *   make snd-cbench CBENCH_SRC=cycles/sound/sjobs_cbench.c CBENCH_CFLAGS=-Ibuild/jobbench \
 *        CBENCH_OBJ=build/hcycles/snd/play/o/bjob.zig.o
 * Each job runs twice: the first with cold caches, as a frame's first job meets them. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../host/bjob.h"
#include "dragon_zx0.h"
#include "scbench.h"

uint32_t bjob_open(uint32_t base, uint32_t size, uint32_t block, uint32_t head);
uint32_t bjob_step(uint32_t head, uint32_t budget);
uint32_t bjob_now(void) { return SND_REG(SND_CYCLES); }

#define MEM (1u << 20) /* the "cart": 1 MiB */
#define N 4096u
static uint8_t g_mem[MEM] __attribute__((aligned(64)));
static uint32_t g_top = 64, g_head;

static uint32_t take(uint32_t bytes) { /* an offset in the cart, 64-aligned */
    uint32_t at = g_top;
    g_top += (bytes + 63u) & ~63u;
    return at;
}
static uint32_t* w(uint32_t off) { return (uint32_t*)(void*)(g_mem + off); }
static uint32_t hash(uint32_t i, uint32_t f) { /* kernels.zig hash */
    uint32_t h = (i * 0x9E3779B1u) ^ (f * 0x85EBCA77u);
    h ^= h >> 15, h *= 0x2C1B3C6Du, h ^= h >> 12, h *= 0x297A2D39u;
    return h ^ (h >> 15);
}

/* Post a job in the block at `blk` and serve it to the end: its cycles (BARD's), its answer. */
static uint32_t job(uint32_t blk, uint32_t op, const uint32_t* a, int n, const char* name, int run) {
    volatile uint32_t* s = bj_slot(w(blk), g_head);
    s[BJ_OP_W] = op;
    for (int i = 0; i < 10; i++) s[BJ_ARG_W + i] = i < n ? a[i] : 0;
    s[BJ_DONE_W] = 0xFFFFFFFFu;
    s[BJ_SEQ_W] = g_head;
    w(blk)[BJ_HEAD_W] = ++g_head;
    cb_mark_t t0 = cb_mark();
    while (bjob_step(g_head, 0xFFFFFFFFu)) {
    }
    uint32_t c = cb_frame(run, t0, 0);
    printf("JOB %s run %d cycles %lu err %lu result %lu\n", name, run, (unsigned long)c, (unsigned long)s[BJ_ERR_W],
           (unsigned long)s[BJ_RESULT_W]);
    return s[BJ_ERR_W];
}

int cbench_run(void) {
    uint32_t blk = take(BJ_BLOCK_BYTES), src = take(sizeof dragon_zx0), pic = take(64000);
    uint32_t pa = take(8 * N), pb = take(8 * N), xf = take(128), zt = take(1024), out = take(4 * N);
    uint32_t s0 = take(16 * N), s1 = take(16 * N), ph = take(64), buf = take(64 * 1024), crcs = take(4 * 256);
    w(blk)[BJ_MAGIC_W] = BJ_MAGIC, w(blk)[BJ_SLOTS_W] = BJ_SLOTS;
    memcpy(g_mem + src, dragon_zx0, sizeof dragon_zx0);
    for (uint32_t i = 0; i < N; i++) { /* points within +-12000 (the cart's sphere and torus) */
        uint32_t h = hash(i, 1), k = hash(i, 2);
        int16_t* p = (int16_t*)(void*)(g_mem + pa + 8 * i);
        int16_t* q = (int16_t*)(void*)(g_mem + pb + 8 * i);
        p[0] = (int16_t)((h & 0x3FFF) - 8192), p[1] = (int16_t)(((h >> 14) & 0x3FFF) - 8192), p[2] = (int16_t)((h >> 18) & 0x1FFF);
        q[0] = (int16_t)((k & 0x3FFF) - 8192), q[1] = (int16_t)(((k >> 14) & 0x3FFF) - 8192), q[2] = (int16_t)((k >> 18) & 0x1FFF);
    }
    int32_t m[17] = {16000, 2000, 1000, -2000, 16000, 500, -1000, -500, 16000, 36000, 160, 88, 320, 176, 320, (int32_t)zt, 256};
    memcpy(w(xf), m, sizeof m);
    w(xf)[17] = 8, w(xf)[18] = 0;
    for (uint32_t d = 1; d < 256; d++) w(zt)[d] = 200u * 65536u / (d << 8); /* setup: libgcc's divide */
    for (uint32_t i = 0; i < 4 * N; i++) w(s0)[i] = i & 3 ? (hash(i, 3) & 0x1FFFF) - 0x10000 : 0;
    for (uint32_t i = 0; i < N; i++) w(s0)[4 * i] = (64 + (hash(i, 4) & 0xFF)) << 16, w(s0)[4 * i + 1] = (20 + (hash(i, 5) & 127)) << 16;
    int32_t phys[11] = {5000, 168 << 16, 150, 1 << 15, 320, 176, 320, 160 << 16, 160 << 16, 1 << 16, -(4 << 16)};
    memcpy(w(ph), phys, sizeof phys);
    for (uint32_t i = 0; i < 16384; i++) w(buf)[i] = hash(i, 0xC2C);
    if (!bjob_open((uint32_t)(uintptr_t)g_mem, MEM, blk, 0)) return 1;
    int bad = 0;
    for (int run = 0; run < 2; run++) {
        bad |= (int)job(blk, 1, (uint32_t[]){src, sizeof dragon_zx0, pic, 64000}, 4, "zx0", run);
        bad |= (int)job(blk, 2, (uint32_t[]){N, pa, pb, 128, xf, out}, 6, "xform", run);
        bad |= (int)job(blk, 3, (uint32_t[]){N, s0, s1, ph, out, 7}, 6, "particles", run);
        bad |= (int)job(blk, 4, (uint32_t[]){buf, 64 * 1024, 8, crcs}, 4, "crc32", run);
    }
    return bad;
}
