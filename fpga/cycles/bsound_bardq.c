/* The BARD queue's cart side where the players are BARD's (host/bardq.h, cycles/snd_mailbox.h): the
 * open is one mailbox command (BARD learns where the cart's block is in DDR); after that ZIGGY never
 * waits. After each cart frame it writes the ring's head in C2S, and copies BARD's answer (S2C:
 * commands taken, position, events) into the cart's block (cycles/bardq_s2c.h). The cart's memory is
 * DDR and ZIGGY's D-cache is write-through, so BARD reads the very bytes the cart wrote. */
#include "bardq_s2c.h"
#include "baudio.h"
#include "haudio.h"

static uint32_t g_block; /* the block's offset in the cart's memory; 0 while none is open */
static uint32_t g_ev;

uint32_t audio_bard_attach(struct w2c_env* e, uint32_t at, uint32_t lead) {
    if (!at) {
        if (g_block) bsound_command(OP_BARD, 0, 0);
        g_block = 0;
        return 0;
    }
    if (!audio_live() || (at & 15u) || (uint64_t)at + 4u * BQ_HEAD_WORDS > e->memory.size) return 0;
    const volatile uint32_t* b = (const volatile uint32_t*)(void*)(e->memory.data + at);
    if (!bq_block_ok(b, (uint32_t)(e->memory.size - at))) return 0;
    g_block = at;
    g_ev = 0;
    SND_REG(SND_C2S + C_BQ_HEAD) = b[BQ_TAIL_W]; /* nothing to take before the cart writes */
    bsound_command(OP_BARD, lead, (uint32_t)(uintptr_t)b);
    return 1;
}

void audio_bard_frame(struct w2c_env* e) {
    if (!g_block) return;
    volatile uint32_t* b = (volatile uint32_t*)(void*)(e->memory.data + g_block);
    SND_REG(SND_C2S + C_BQ_HEAD) = b[BQ_HEAD_W];
    bq_s2c_collect(&SND_REG(SND_S2C), b, &g_ev);
}
