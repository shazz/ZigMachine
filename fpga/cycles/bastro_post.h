/* ASTROLABE's request from ZIGGY's side (SPIKE, docs/ARM_FPU_COPROC.md): bastro.c's protocol,
 * here with the mailbox, the cart's memory and the clock passed in, so tests/tb/astro_post_test.c
 * runs it natively against a scripted glass. The words are bastro_box.h's. */
#ifndef ZM_BASTRO_POST_H
#define ZM_BASTRO_POST_H

#include <stdint.h>

#include "bastro_box.h"

#define BASTRO_UNSERVED 0xFFFFFFFFu /* nobody served it: run the machine's own code */
#define BASTRO_TAKE_US 50000u       /* glass naps 1 ms when idle: a live worker takes it far sooner */
#define BASTRO_DONE_US 10000000u

typedef struct {
    volatile uint32_t* box; /* the mailbox's 1024 words */
    uint8_t* mem;           /* the cart's memory (cart address 0) */
    uint32_t size, mem_off; /* its bytes; its offset in the DDR window */
    uint32_t (*micros)(void);
    uint32_t seq, dead_beat;
    int dead;               /* a request was not taken: nothing more until glass's BEAT moves */
    int arrays;             /* the last request had an array op (the D-cache must go) */
    uint32_t untaken, timeouts, arm_ns;
} bastro_ctx;

static inline uint32_t bastro_rd(const bastro_ctx* c, uint32_t a) { return *(const uint32_t*)(c->mem + a); }
static inline void bastro_wr(bastro_ctx* c, uint32_t a, uint32_t v) { *(uint32_t*)(c->mem + a) = v; }

static inline int bastro_list_ok(const bastro_ctx* c, uint32_t desc, uint32_t count) {
    return count <= ASTRO_MAX_COUNT && desc % 8 == 0 && desc >= 8 &&
           (uint64_t)desc + (uint64_t)count * ASTRO_DESC_WORDS * 4 <= c->size;
}

static inline int bastro_alive(bastro_ctx* c) {
    volatile uint32_t* b = c->box;
    if (b[ASTRO_MAGIC] != ASTRO_ID || b[ASTRO_VERSION] != ASTRO_PROTO) return 0;
    if (c->dead && b[ASTRO_BEAT] == c->dead_beat) return 0;
    c->dead = 0;
    return 1;
}

/* The words glass reads (glass/src/astro_box.zig serveOne): W_OP, then a scalar op's three
 * scalars or an array op's W_N .. W_C and S0. Returns 1 for an array op. */
static inline int bastro_copy_in(bastro_ctx* c, uint32_t at, uint32_t slot) {
    uint32_t op = bastro_rd(c, at);
    int array = (op & ASTRO_OP_MASK) >= ASTRO_OP_VADD;
    c->box[slot + ASTRO_W_OP] = op;
    uint32_t lo = array ? ASTRO_W_N : ASTRO_W_S0, hi = array ? ASTRO_W_C : ASTRO_W_S0 + 5;
    for (uint32_t w = lo; w <= hi; w++) c->box[slot + w] = bastro_rd(c, at + 4 * w);
    if (array) {
        c->box[slot + ASTRO_W_S0] = bastro_rd(c, at + 4 * ASTRO_W_S0);
        c->box[slot + ASTRO_W_S0 + 1] = bastro_rd(c, at + 4 * ASTRO_W_S0 + 4);
    }
    return array;
}

static inline int bastro_wait(bastro_ctx* c, uint32_t word, uint32_t seq, uint32_t us) {
    uint32_t t0 = c->micros();
    while (c->box[word] != seq)
        if (c->micros() - t0 >= us) return 0;
    return 1;
}

/* One call: BASTRO_UNSERVED (no live worker, or not taken in time: withdrawn), else hwAstro's
 * answer with every descriptor's W_STATUS and W_R written back. Taken but not done in time:
 * ST_TIMEOUT, never a rerun here (the ARM may still write an in-place array). */
static inline uint32_t bastro_post(bastro_ctx* c, uint32_t desc, uint32_t count) {
    volatile uint32_t* b = c->box;
    c->arrays = 0;
    if (count == 0 || !bastro_alive(c)) return BASTRO_UNSERVED;
    if (!bastro_list_ok(c, desc, count)) return ASTRO_ST_BAD_DESC;
    for (uint32_t i = 0; i < count; i++)
        c->arrays |= bastro_copy_in(c, desc + i * ASTRO_DESC_WORDS * 4, ASTRO_DESC0 + i * ASTRO_DESC_WORDS);
    b[ASTRO_COUNT] = count;
    b[ASTRO_MEM_OFF] = c->mem_off;
    b[ASTRO_MEM_SIZE] = c->size;
    uint32_t seq = ++c->seq ? c->seq : ++c->seq; /* never 0: glass ignores SEQ 0 */
    b[ASTRO_SEQ] = seq; /* an IO store: after every posted DDR store (soc/zm_io_fence.py) */
    if (!bastro_wait(c, ASTRO_TAKEN, seq, BASTRO_TAKE_US)) {
        b[ASTRO_SEQ] = 0; /* withdrawn: a worker that wakes later finds nothing */
        c->dead = 1, c->dead_beat = b[ASTRO_BEAT], c->untaken++;
        return BASTRO_UNSERVED;
    }
    if (!bastro_wait(c, ASTRO_DONE, seq, BASTRO_DONE_US)) return c->timeouts++, ASTRO_ST_TIMEOUT;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t at = desc + i * ASTRO_DESC_WORDS * 4, slot = ASTRO_DESC0 + i * ASTRO_DESC_WORDS;
        bastro_wr(c, at + 4 * ASTRO_W_STATUS, b[slot + ASTRO_W_STATUS]);
        bastro_wr(c, at + 4 * ASTRO_W_R, b[slot + ASTRO_W_R]);
        bastro_wr(c, at + 4 * ASTRO_W_R + 4, b[slot + ASTRO_W_R + 1]);
    }
    c->arm_ns = b[ASTRO_ARM_NS];
    return b[ASTRO_RET];
}

#endif
