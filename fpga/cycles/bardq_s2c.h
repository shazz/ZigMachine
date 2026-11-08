/* The BARD queue's answer across the S2C bank (cycles/snd_mailbox.h S_BQ..): BARD publishes, ZIGGY
 * copies into the cart's block (host/bardq.h) after the cart's frame. The bank is LUTRAM read past
 * both D-caches, so no flush on either side. Events go in S_BQ_SLOTS slots, then the count: ZIGGY
 * re-reads the count after the slots, and an event a later one overwrote meanwhile (or that BARD
 * made while ZIGGY was more than S_BQ_SLOTS behind) is counted lost in the cart's block.
 * Header-only: cycles/sound/sbardq.c, cycles/bsound_bardq.c, fpga/tests/test_bard_queue.py. */
#ifndef ZM_BARDQ_S2C_H
#define ZM_BARDQ_S2C_H

#include <stdint.h>

#include "../host/bardq.h"
#include "snd_mailbox.h"

static inline void bq_s2c_boot(volatile uint32_t* s2c) {
    for (uint32_t i = S_BQ; i < S_BQ_EV + 2u * S_BQ_SLOTS; i++) s2c[i] = 0;
}

/* BARD: the commands taken and the position (each stored only when it changed). */
static inline void bq_s2c_state(volatile uint32_t* s2c, uint32_t tail, const bq_state* s, uint32_t evn) {
    uint32_t w[3] = {tail, s->pos, evn << 1 | (s->anchored ? 1u : 0u)};
    for (uint32_t i = 0; i < 3; i++)
        if (s2c[S_BQ + i] != w[i]) s2c[S_BQ + i] = w[i];
}

/* BARD: event number `n` (the count before it) into its slot; the count follows in bq_s2c_state. */
static inline void bq_s2c_event(volatile uint32_t* s2c, uint32_t n, const uint32_t ev[3]) {
    volatile uint32_t* slot = &s2c[S_BQ_EV + 2u * (n % S_BQ_SLOTS)];
    slot[0] = ev[0];
    slot[1] = (ev[1] & 0xFFu) | ev[2] << 8;
}

/* ZIGGY: the answer into the cart's block `b`; `seen` the events copied so far. */
static inline void bq_s2c_collect(const volatile uint32_t* s2c, volatile uint32_t* b, uint32_t* seen) {
    uint32_t tail = s2c[S_BQ_TAIL], head = b[BQ_HEAD_W], old = b[BQ_TAIL_W];
    if (tail - old <= head - old) b[BQ_TAIL_W] = tail; /* never past what the cart wrote */
    uint32_t evn = s2c[S_BQ_EVN];
    if (evn & 1u) {
        b[BQ_POS_W] = s2c[S_BQ_POS];
        b[BQ_ANCHORED_W] = 1;
    }
    uint32_t n = evn >> 1, lost = 0;
    for (uint32_t i = *seen; i != n; i++) {
        const volatile uint32_t* slot = &s2c[S_BQ_EV + 2u * (i % S_BQ_SLOTS)];
        uint32_t t = slot[0], ka = slot[1];
        /* The count now: event i's slot holds a later one if BARD has made S_BQ_SLOTS since (before
         * this frame, or while the slot was being read). */
        if ((s2c[S_BQ_EVN] >> 1) - i > S_BQ_SLOTS) {
            lost++;
            continue;
        }
        bq_cart_event(b, t, ka & 0xFFu, ka >> 8);
    }
    b[BQ_EV_LOST_W] = b[BQ_EV_LOST_W] + lost;
    *seen = n;
}

#endif
