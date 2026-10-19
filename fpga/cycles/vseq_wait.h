/* The sequencer's waits and calls (vseq.c's only, static inline), and the probe around them:
 * under ZM_VSTAT each wait that waits, each HBL handler and each vseq_decide is timed with the
 * cycle counter into vseq (vseq.h), for cycles/vstat.c. Without it they are vseq.c's plain loops. */
#ifndef ZM_VSEQ_WAIT_H
#define ZM_VSEQ_WAIT_H

#include <stdint.h>

#include "host.h"
#include "vboard.h"
#include "vseq.h"

static inline void wait_bits(uint32_t bits) {
    while ((zmv_status() & bits) != bits) {
    }
}

/* wait_bits, returning the cycles it waited (ZM_VSTAT; 0 without). Only a wait that waits is
 * timed: one counter read after the loop is all the probe adds to the sequencer's path. */
static inline uint32_t wait_timed(uint32_t bits) {
    if ((zmv_status() & bits) == bits) return 0;
#ifdef ZM_VSTAT
    uint32_t t0 = board_cycles();
    wait_bits(bits);
    return board_cycles() - t0;
#else
    wait_bits(bits);
    return 0;
#endif
}

/* An HBL handler, timed under ZM_VSTAT (while the last pass mixes and stores). */
static inline void hbl(struct w2c_env* e, uint16_t id, u32 p, u32 y, u32 pos) {
#ifdef ZM_VSTAT
    uint32_t t0 = board_cycles();
    w2c_env_hblDispatch(e, id, p, y, pos);
    vseq.hbl += board_cycles() - t0;
#else
    w2c_env_hblDispatch(e, id, p, y, pos);
#endif
}

/* vseq_decide, timed under ZM_VSTAT (it runs while the line before is composited). */
static inline int decide(int y) {
#ifdef ZM_VSTAT
    uint32_t t0 = board_cycles();
    int skip = vseq_decide(y);
    vseq.plan += board_cycles() - t0;
    return skip;
#else
    return vseq_decide(y);
#endif
}

#endif
