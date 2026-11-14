/* The BARD queue's players side (host/bardq.h): the cart's commands into demo-audio.wasm's queue
 * (apps/zig/demo_audio_sidlive.zig), as the worklet's bardQueue stages them, and the queue's answer
 * read back, as its bardState reads it. The same on the native host, on ZIGGY with the players and on
 * BARD; only where the block lives differs (the cart's memory, or its DDR read past BARD's D-cache). */
#include <string.h>

#include "bardq.h"
#include "haudio.h"

/* cycles/baudio.c: the debug page's music block (F11 "SID" / "AY"); audio_soft.c: nothing.
 * kind 0 closed, 1 SID live, 2 AY (the queue's first AY write, below). */
void audio_backend_bard(int kind);

#define BQ_AY_BASE 0xA000u /* libs/zig/bard.zig AY_BASE: an AY command's addr is $A000 + chip x 16 + reg */
static int g_kind;         /* what the page was told for this queue: 1 until an AY command shows */

void bq_open(uint32_t lead) {
    w2c_audio_audioBardOpen(&g_aud.player, lead);
    g_kind = 1;
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
    if (!w2c_audio_audioBardActive(p)) { /* counted, not staged: song RAM is someone else's (the worklet's rule) */
        w2c_audio_audioBardQueue(p, head - tail);
        return head;
    }
    for (; tail != head; tail++) {
        const volatile uint32_t* c = bq_cmd(b, tail);
        if (c[3] != tail) break; /* not whole yet (the board: a store still on its way to DDR) */
        if (g_kind == 1 && (c[1] & 0xF000u) == BQ_AY_BASE) audio_backend_bard(g_kind = 2);
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
    s->active = w2c_audio_audioBardActive(p);
}

void bq_event(uint32_t i, uint32_t ev[3]) {
    w2c_audio* p = &g_aud.player;
    uint32_t cap = w2c_audio_audioBardEventCap(p);
    const uint32_t* r = (const uint32_t*)(const void*)(g_aud.memory.data + w2c_audio_audioBardEventsPtr(p));
    memcpy(ev, r + 4u * (i % cap), 3 * sizeof(uint32_t));
}
