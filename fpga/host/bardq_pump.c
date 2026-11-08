/* The BARD queue's players side (host/bardq.h): the cart's commands into demo-audio.wasm's queue
 * (apps/zig/demo_audio_sidlive.zig), as the worklet's bardQueue stages them, and the queue's answer
 * read back, as its bardState reads it. The same on the native host, on ZIGGY with the players and on
 * BARD; only where the block lives differs (the cart's memory, or its DDR read past BARD's D-cache). */
#include <string.h>

#include "bardq.h"
#include "haudio.h"

void audio_backend_bard(int on); /* cycles/baudio.c: the debug page's music block (F11 "SID"); audio_soft.c: nothing */

void bq_open(uint32_t lead) {
    w2c_audio_audioBardOpen(&g_aud.player, lead);
    audio_backend_bard(1);
}
void bq_close(void) {
    w2c_audio_audioBardClose(&g_aud.player);
    audio_backend_bard(0);
}

/* The staged batch queued, as the worklet's bardQueue does. */
static void queue(uint32_t n) {
    if (n) w2c_audio_audioBardQueue(&g_aud.player, n);
}

uint32_t bq_pump(const volatile uint32_t* b, uint32_t tail, uint32_t head) {
    w2c_audio* p = &g_aud.player;
    uint32_t cap = b[BQ_CAP_W], stage_cap = w2c_audio_audioBardStageCap(p), n = 0;
    uint32_t* stage = (uint32_t*)(void*)(g_aud.memory.data + w2c_audio_audioBardStagePtr(p));
    if (head - tail > cap) return tail; /* not a head this ring can have: take nothing */
    for (; tail != head; tail++) {
        const volatile uint32_t* c = bq_cmd(b, tail);
        if (c[3] != tail) break; /* not whole yet (the board: a store still on its way to DDR) */
        uint32_t* s = stage + 4u * n;
        s[0] = c[0];
        s[1] = c[1];
        s[2] = c[2];
        s[3] = 0;
        if (++n == stage_cap) {
            queue(n);
            n = 0;
        }
    }
    queue(n);
    return tail;
}

void bq_read(bq_state* s) {
    w2c_audio* p = &g_aud.player;
    s->pos = w2c_audio_audioBardPosition(p);
    s->anchored = w2c_audio_audioBardAnchored(p);
    s->ev_count = w2c_audio_audioBardEventCount(p);
}

void bq_event(uint32_t i, uint32_t ev[3]) {
    w2c_audio* p = &g_aud.player;
    uint32_t cap = w2c_audio_audioBardEventCap(p);
    const uint32_t* r = (const uint32_t*)(const void*)(g_aud.memory.data + w2c_audio_audioBardEventsPtr(p));
    memcpy(ev, r + 4u * (i % cap), 3 * sizeof(uint32_t));
}
