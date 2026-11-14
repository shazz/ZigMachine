/* BARD jobs' cart side where BARD serves them (host/bjob.h, cycles/snd_mailbox.h OP_JOB, table 1.24).
 * The open is one mailbox command (BARD learns where the cart's memory and block are in DDR); a kick is
 * one C2S store of the jobs posted. BARD takes a slot only once its seq, which the cart writes last, is in
 * DDR (and the board's IO stores already wait for ZIGGY's posted DDR stores: soc/zm_io_fence.py). BARD answers in the cart's
 * DDR, behind ZIGGY's write-through D-cache: a poll drops the slot's lines before it reads `done`, and
 * once a job is done the whole D-cache (whatever ZIGGY held of the job's outputs is older than BARD's
 * stores). The cart never waits on the mailbox after the open. */
#include "../host/bjob.h"
#include "baudio.h"
#include "bdinval.h"
#include "haudio.h"
#include "snd_mailbox.h"

#define JOB_WAIT 50000000u /* sys clocks (0.5 s): a job train far longer than any frame, short of a hang */

static uint32_t g_block; /* the block's offset in the cart's memory; 0 while none is open */

static volatile uint32_t* block(struct w2c_env* e) { return (volatile uint32_t*)(void*)(e->memory.data + g_block); }

static uint32_t job_open(struct w2c_env* e, uint32_t at) {
    if (!at) {
        if (g_block) bsound_command_len(OP_JOB, 0, 0, 0);
        g_block = 0;
        return 0;
    }
    if (!audio_live() || !bj_block_ok(e->memory.data, e->memory.size, at)) return 0;
    g_block = at;
    SND_REG(SND_C2S + C_JOB_HEAD) = block(e)[BJ_HEAD_W]; /* nothing to take before the cart posts */
    bsound_command_len(OP_JOB, at, (uint32_t)(uintptr_t)e->memory.data, (uint32_t)e->memory.size);
    return 1;
}

/* Job `t` answered? Its slot's lines dropped first: BARD wrote them in DDR. */
static uint32_t job_poll(struct w2c_env* e, uint32_t t) {
    volatile uint32_t* j = bj_slot(block(e), t);
    bdi_span((uintptr_t)j, (uintptr_t)(j + BJ_JOB_WORDS));
    if (j[BJ_DONE_W] != t) return 0;
    bdi_inval_all(); /* the job's outputs, as BARD stored them */
    return 1;
}

static uint32_t job_wait(struct w2c_env* e, uint32_t t) {
    uint32_t t0 = SND_REG(SND_CYCLES);
    while (!job_poll(e, t))
        if (SND_REG(SND_CYCLES) - t0 > JOB_WAIT) return 0; /* BARD never answered: the cart serves */
    return 1;
}

uint32_t audio_bard_job(struct w2c_env* e, uint32_t op, uint32_t arg) {
    if (op == BJ_HOST_OPEN) return job_open(e, arg);
    if (!g_block) return 0;
    if (op == BJ_HOST_KICK) {
        SND_REG(SND_C2S + C_JOB_HEAD) = arg;
        return 1;
    }
    if (op == BJ_HOST_POLL) return job_poll(e, arg);
    if (op == BJ_HOST_WAIT) return job_wait(e, arg);
    return 0;
}
