/* BARD jobs on the sound CPU (host/bjob.h, cycles/snd_mailbox.h OP_JOB, table 1.24): the server is
 * libs/zig/bard_jobs/server.zig, built rv32i + Zmmul (cycles/sound.mk BJOB_OBJ, entry
 * libs/zig/bard_job_rv32.zig), the very source the cart's wasm serves with where BARD is absent.
 * Each turn of smain.c's loop: when ZIGGY's head (C2S) moved, the D-cache is dropped (the jobs and
 * their inputs, as the cart wrote them) and the server runs at most SJ_BUDGET cycles, so a job of a
 * few Mcycles is spread between the audio renders and the music never starves. */
#include <stdint.h>

#include "../dflush.h"
#include "../snd_mailbox.h"
#include "sjobs.h"

#define SJ_BUDGET 100000u /* cycles a turn (1 ms): the render lead is 4 frames */

uint32_t bjob_open(uint32_t base, uint32_t size, uint32_t block, uint32_t head);
void bjob_close(void);
uint32_t bjob_step(uint32_t head, uint32_t budget);
uint32_t bjob_now(void);

uint32_t bjob_now(void) { return SND_REG(SND_CYCLES); }

static int g_open;
static uint32_t g_head; /* the head last taken from C2S */
static uint32_t g_more; /* bjob_step's last answer: 0 idle, 1 a job half done, 2 a slot not whole yet */

void sjobs_open(uint32_t base, uint32_t size, uint32_t block) {
    bjob_close();
    g_open = 0;
    g_more = 0;
    if (!base) return;
    zm_dflush(); /* the block's header, as the cart just wrote it */
    g_head = SND_REG(SND_C2S + C_JOB_HEAD);
    g_open = bjob_open(base, size, block, g_head) != 0;
}

void sjobs_take(void) {
    if (!g_open) return;
    uint32_t head = SND_REG(SND_C2S + C_JOB_HEAD);
    if (head == g_head && !g_more) return;
    if (head != g_head || g_more == 2) zm_dflush(); /* new jobs, or one still landing */
    g_head = head;
    g_more = bjob_step(head, SJ_BUDGET);
}
