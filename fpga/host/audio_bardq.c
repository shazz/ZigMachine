/* The BARD queue's cart side where the players run on this CPU (host/bardq.h): the native host and
 * ZIGGY with ZM_AUDIO=1. env.hostBardAttach opens SID live on the players; after each cart frame the
 * ring's new commands go to them (host/bardq_pump.c) and their answer goes into the cart's block, as
 * docs/sealed-loader.js's bardFrame / bardPublish do. With the players on BARD, cycles/bsound_bardq.c. */
#include "bardq.h"
#include "haudio.h"

static uint32_t g_block; /* the block's offset in the cart's memory; 0 while none is open */
static uint32_t g_ev;    /* the players' events taken so far */

static volatile uint32_t* block(struct w2c_env* e) { return (volatile uint32_t*)(void*)(e->memory.data + g_block); }

uint32_t audio_bard_attach(struct w2c_env* e, uint32_t at, uint32_t lead) {
    if (!at) {
        if (g_block && audio_live()) bq_close();
        g_block = 0;
        return 0;
    }
    if (!audio_live() || (at & 15u) || (uint64_t)at + 4u * BQ_HEAD_WORDS > e->memory.size) return 0;
    if (!bq_block_ok((const volatile uint32_t*)(void*)(e->memory.data + at), (uint32_t)(e->memory.size - at))) return 0;
    g_block = at;
    g_ev = 0;
    bq_open(lead);
    return 1;
}

void audio_bard_frame(struct w2c_env* e) {
    if (!g_block) return;
    volatile uint32_t* b = block(e);
    b[BQ_TAIL_W] = bq_pump(b, b[BQ_TAIL_W], b[BQ_HEAD_W]);
    bq_state s;
    bq_read(&s);
    if (!s.active) return; /* closed (a song took over): nothing more comes back, as on the page */
    b[BQ_POS_W] = s.pos;
    b[BQ_ANCHORED_W] = s.anchored;
    if (s.ev_count - g_ev > 64u) g_ev = s.ev_count - 64u; /* sid_live.zig EV_CAP: lapped, the newest */
    for (; g_ev != s.ev_count; g_ev++) {
        uint32_t ev[3];
        bq_event(g_ev, ev);
        bq_cart_event(b, ev[0], ev[1], ev[2]);
    }
}
