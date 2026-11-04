/* KOS's C: request block (glass/src/map_cart.zig KOS_DRIVE_*, read by glass/src/kos_drive.zig):
 * what ZIGGY's firmware writes to ask glass for sectors of the SD card, and how it reads the
 * answer. The words first, the magic last, so a block whose magic and check hold is whole; the
 * answer is KD_DONE then KD_ACK = the sequence. Header-only so tests/tb/kosreq_test.c runs it
 * over a plain buffer. */
#ifndef ZM_BKOSREQ_H
#define ZM_BKOSREQ_H

#include <stdint.h>

#include "glass_cart.h"

static inline uint32_t bkosreq_check(const volatile uint32_t* w) {
    return ~(KOS_DRIVE_MAGIC ^ w[KD_SEQ] ^ w[KD_UNIT] ^ w[KD_SECTOR] ^ w[KD_COUNT] ^ w[KD_OFFSET]);
}

static inline void bkosreq_write(volatile uint32_t* w, uint32_t seq, uint32_t unit, uint32_t sector, uint32_t count,
                                 uint32_t offset) {
    w[KD_MAGIC] = 0; /* a half-written block is no block */
    w[KD_ACK] = 0;
    w[KD_DONE] = 0;
    w[KD_SEQ] = seq;
    w[KD_UNIT] = unit;
    w[KD_SECTOR] = sector;
    w[KD_COUNT] = count;
    w[KD_OFFSET] = offset;
    w[KD_CHECK] = bkosreq_check(w);
    w[KD_MAGIC] = KOS_DRIVE_MAGIC;
}

/* The sectors glass read for request `seq` (0: refused, or an I/O error), or -1 while it has not answered. */
static inline int32_t bkosreq_answer(const volatile uint32_t* w, uint32_t seq) {
    if (w[KD_ACK] != seq) return -1;
    uint32_t n = w[KD_DONE];
    return n <= KOS_DRIVE_MAX_SECTORS ? (int32_t)n : 0;
}

#endif
