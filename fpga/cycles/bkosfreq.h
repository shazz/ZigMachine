/* KOS's C: writes, the request block (glass/src/map_cart.zig KOS_FILE_*, served by glass/src/kos_file.zig):
 * what ZIGGY's firmware writes to hand glass a whole-file request (docs/KOS_GEMDOS.md §7), and how it
 * reads the answer. The words first, the magic last, so a block whose magic and check hold is whole; the
 * answer is KF_DONE (a TOS code) then KF_ACK = the sequence. Header-only so tests/tb/kosfreq_test.c runs
 * it over a plain buffer. `f` is the request's words KF_OP .. KF_PATH2_LEN, in that order. */
#ifndef ZM_BKOSFREQ_H
#define ZM_BKOSFREQ_H

#include <stdint.h>

#include "glass_cart.h"

#define KF_FIELDS (KF_PATH2_LEN - KF_OP + 1)

static inline void bkosfreq_write(volatile uint32_t* w, uint32_t seq, const uint32_t f[KF_FIELDS]) {
    w[KF_MAGIC] = 0; /* a half-written block is no block */
    w[KF_ACK] = 0;
    w[KF_DONE] = 0;
    w[KF_SEQ] = seq;
    uint32_t check = KOS_FILE_MAGIC ^ seq;
    for (int i = 0; i < KF_FIELDS; i++) {
        w[KF_OP + i] = f[i];
        check ^= f[i];
    }
    w[KF_CHECK] = ~check;
    w[KF_MAGIC] = KOS_FILE_MAGIC;
}

/* glass serves this block (glass/src/kos_file.zig writes KOS_FILE_READY at KOS_FILE_READY_FROM_TOP each poll). */
static inline int bkosfreq_ready(uint32_t word) { return word == KOS_FILE_READY; }

/* glass's answer to request `seq` (a TOS code, < 0 an error), or 1 << 31 | 1 while it has not answered. */
#define BKOSF_WAIT 0x80000001u
static inline uint32_t bkosfreq_answer(const volatile uint32_t* w, uint32_t seq) {
    return w[KF_ACK] == seq ? w[KF_DONE] : BKOSF_WAIT;
}

#endif
