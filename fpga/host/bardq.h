/* The BARD queue (system table 1.12, decisions.md 2026-11-07 "The BARD queue"): the cart's block
 * (libs/zig/bard.zig, the layout below) and the two sides that serve it where native C runs.
 *   players side (host/bardq_pump.c): a batch of the ring's entries into demo-audio.wasm's queue
 *     (apps/zig/demo_audio_sidlive.zig), its position and events read back. On the native host and
 *     on ZIGGY with the players (ZM_AUDIO=1) it reads the cart's memory; on BARD the cart's DDR.
 *   cart side: host/audio_bardq.c where the players are this CPU's, cycles/bsound_bardq.c where
 *     they are BARD's (the head through C2S, the answer through S2C: cycles/snd_mailbox.h).
 * docs/sealed-loader.js bardDrain / bardPublish are the page's copy; apps/bard_queue_check.mjs holds
 * the three to the same samples. Header-only helpers, so fpga/tests/test_bard_queue.py compiles them. */
#ifndef ZM_BARDQ_H
#define ZM_BARDQ_H

#include <stdint.h>

#define BQ_MAGIC 0x51424d5au /* "ZMBQ" */
#define BQ_CAP_MAX 4096u
#define BQ_EV_CAP_MAX 256u
/* The header's words: C written by the cart, H by the host. */
enum {
    BQ_MAGIC_W = 0, BQ_CAP_W = 1, BQ_EV_CAP_W = 2, BQ_LEAD_W = 3, /* C */
    BQ_HEAD_W = 4,                                                /* C: commands written */
    BQ_TAIL_W = 5,                                                /* H: commands taken */
    BQ_DROPPED_W = 6,                                             /* C */
    BQ_POS_W = 7, BQ_ANCHORED_W = 8, BQ_EV_HEAD_W = 9,            /* H */
    BQ_EV_TAIL_W = 10,                                            /* C */
    BQ_EV_LOST_W = 11,                                            /* H */
    BQ_HEAD_WORDS = 16
};

static inline int bq_pow2(uint32_t v) { return v && !(v & (v - 1)); }

/* The block's size in bytes (header, commands, events: 16 bytes an entry). */
static inline uint32_t bq_bytes(uint32_t cap, uint32_t ev_cap) { return 4u * BQ_HEAD_WORDS + 16u * (cap + ev_cap); }

/* A block the cart handed over: its magic, power-of-two rings, and all of it inside `room` bytes. */
static inline int bq_block_ok(const volatile uint32_t* b, uint32_t room) {
    if (room < 4u * BQ_HEAD_WORDS || b[BQ_MAGIC_W] != BQ_MAGIC) return 0;
    uint32_t cap = b[BQ_CAP_W], ev = b[BQ_EV_CAP_W];
    return bq_pow2(cap) && cap <= BQ_CAP_MAX && bq_pow2(ev) && ev <= BQ_EV_CAP_MAX && bq_bytes(cap, ev) <= room;
}

/* Command `i` of the ring: {t, addr, value, seq}; whole only when seq == i. */
static inline const volatile uint32_t* bq_cmd(const volatile uint32_t* b, uint32_t i) {
    return b + BQ_HEAD_WORDS + 4u * (i & (b[BQ_CAP_W] - 1u));
}

/* One event into the cart's ring (t, kind, arg; seq = its index), or counted lost when full. */
static inline void bq_cart_event(volatile uint32_t* b, uint32_t t, uint32_t kind, uint32_t arg) {
    uint32_t head = b[BQ_EV_HEAD_W], cap = b[BQ_EV_CAP_W];
    if (head - b[BQ_EV_TAIL_W] >= cap) {
        b[BQ_EV_LOST_W] = b[BQ_EV_LOST_W] + 1u;
        return;
    }
    volatile uint32_t* e = b + BQ_HEAD_WORDS + 4u * b[BQ_CAP_W] + 4u * (head & (cap - 1u));
    e[0] = t;
    e[1] = kind;
    e[2] = arg;
    e[3] = head;
    b[BQ_EV_HEAD_W] = head + 1u;
}

/* The players' side (host/bardq_pump.c). */
typedef struct bq_state {
    uint32_t pos, anchored, ev_count, active; /* active 0: the queue closed, every other field 0 */
} bq_state;
void bq_open(uint32_t lead);
void bq_close(void);
/* Commands [tail, head) of `b` into the players, in batches; stops at the first one not whole.
 * Returns the new tail. */
uint32_t bq_pump(const volatile uint32_t* b, uint32_t tail, uint32_t head);
void bq_read(bq_state* s);
/* Event `i` (absolute: i < ev_count, within the last EV_CAP) as t, kind, arg. */
void bq_event(uint32_t i, uint32_t ev[3]);

/* The cart's side (host/audio_bardq.c, cycles/bsound_bardq.c): env.hostBardAttach, and the frame's
 * hand-over after the cart's frame (host/audio_bridge.c). */
struct w2c_env;
uint32_t audio_bard_attach(struct w2c_env* e, uint32_t block, uint32_t lead);
void audio_bard_frame(struct w2c_env* e);

#endif
