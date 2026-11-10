/* ZIGNIC's request block (glass/src/map_cart.zig NET_*, served by glass/src/net_card.zig): what ZIGGY's firmware
 * writes to hand glass one env.netOp request (docs/GEM_NET.md N2), and how it reads the answer. The words first,
 * the magic last, so a block whose magic and check hold is whole; the answer is NB_OUT.. and NB_DONE, then
 * NB_ACK = the sequence last. Header-only so tests/tb/netreq_test.c runs it over a plain buffer. `f` is the
 * request's words NB_OP .. NB_HOST_LEN (op, sock, a0, a1, buf, len, host, host_len; buf/host window offsets). */
#ifndef ZM_BNETREQ_H
#define ZM_BNETREQ_H

#include <stdint.h>

#include "glass_cart.h"

#define NB_FIELDS (NB_HOST_LEN - NB_OP + 1)

static inline void bnetreq_write(volatile uint32_t* w, uint32_t seq, const uint32_t f[NB_FIELDS]) {
    w[NB_MAGIC] = 0; /* a half-written block is no block */
    w[NB_ACK] = 0;
    w[NB_TAKEN] = 0;
    w[NB_SEQ] = seq;
    uint32_t check = NET_MAGIC ^ seq;
    for (int i = 0; i < NB_FIELDS; i++) {
        w[NB_OP + i] = f[i];
        check ^= f[i];
    }
    w[NB_CHECK] = ~check;
    w[NB_MAGIC] = NET_MAGIC;
}

/* glass answered request `seq`: 1 (and its words are in w[NB_DONE], w[NB_OUT..]), else 0. */
static inline int bnetreq_answered(const volatile uint32_t* w, uint32_t seq) { return w[NB_ACK] == seq; }

#endif
