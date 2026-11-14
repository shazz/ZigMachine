/* BARD jobs (zg.bard.job, system table 1.24, decisions.md 2026-11-13): the cart's job block as C sees it,
 * the copy of libs/zig/bard_jobs/layout.zig (fpga/tests/test_bard_job.py holds the two equal). The cart
 * posts jobs in a ring in its own memory; a server outside its frame runs them (BARD on the board:
 * cycles/sound/sjobs.c running libs/zig/bard_jobs/server.zig, built rv32i + Zmmul). env.hostBardJob is
 * the cart's one entry: cycles/bsound_job.c where BARD serves; host/audio_bardjob.c elsewhere (none: the
 * cart serves its own jobs, the same kernels, so the same bytes). */
#ifndef ZM_BJOB_H
#define ZM_BJOB_H

#include <stdint.h>

#define BJ_MAGIC 0x4a424d5au /* "ZMBJ" */
#define BJ_SLOTS 8u
#define BJ_HEAD_WORDS 8u
#define BJ_JOB_WORDS 16u
#define BJ_BLOCK_BYTES (4u * (BJ_HEAD_WORDS + BJ_SLOTS * BJ_JOB_WORDS))
enum { BJ_MAGIC_W = 0, BJ_SLOTS_W = 1, BJ_HEAD_W = 2 }; /* the header: the cart's words */
enum { BJ_OP_W = 0, BJ_SEQ_W = 1, BJ_DONE_W = 2, BJ_ERR_W = 3, BJ_CYCLES_W = 4, BJ_RESULT_W = 5, BJ_ARG_W = 6 };
enum { BJ_HOST_OPEN = 0, BJ_HOST_KICK = 1, BJ_HOST_POLL = 2, BJ_HOST_WAIT = 3 }; /* hostBardJob's ops */

/* Job `t`'s slot in the block at `b`. */
static inline volatile uint32_t* bj_slot(volatile uint32_t* b, uint32_t t) {
    return b + BJ_HEAD_WORDS + BJ_JOB_WORDS * (t & (BJ_SLOTS - 1u));
}

/* A block the cart can have opened: 16-aligned, inside its memory, the magic and the ring's size. */
static inline int bj_block_ok(const uint8_t* mem, uint64_t size, uint32_t at) {
    if (!at || (at & 15u) || (uint64_t)at + BJ_BLOCK_BYTES > size) return 0;
    const volatile uint32_t* b = (const volatile uint32_t*)(const void*)(mem + at);
    return b[BJ_MAGIC_W] == BJ_MAGIC && b[BJ_SLOTS_W] == BJ_SLOTS;
}

#endif
