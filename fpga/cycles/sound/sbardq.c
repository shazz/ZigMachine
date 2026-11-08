/* The BARD queue on the sound CPU (host/bardq.h, cycles/snd_mailbox.h OP_BARD): BARD reads the cart's
 * ring in DDR itself, so ZIGGY never waits for it. Each turn of the loop: if ZIGGY's head (C2S) moved
 * past what was taken, the D-cache is dropped and the whole entries are queued (host/bardq_pump.c, an
 * entry still on its way to DDR waits for the next turn); after a render, the answer goes to S2C. */
#include <stdint.h>

#include "../bardq_s2c.h"
#include "../dflush.h"
#include "sbardq.h"

static const volatile uint32_t* g_block; /* the cart's block in DDR; NULL while closed */
static uint32_t g_tail, g_ev;

#define C2S(w) SND_REG(SND_C2S + (w))

void sbardq_boot(void) { bq_s2c_boot(&SND_REG(SND_S2C)); }

void sbardq_open(uint32_t addr, uint32_t lead) {
    if (g_block) bq_close();
    g_block = 0;
    bq_s2c_boot(&SND_REG(SND_S2C));
    if (!addr) return;
    zm_dflush(); /* the block's header, as the cart just wrote it */
    const volatile uint32_t* b = (const volatile uint32_t*)(uintptr_t)addr;
    if (!bq_block_ok(b, bq_bytes(BQ_CAP_MAX, BQ_EV_CAP_MAX))) return; /* ZIGGY checked it against the cart */
    g_block = b;
    g_tail = b[BQ_TAIL_W];
    g_ev = 0;
    bq_open(lead);
}

void sbardq_take(void) {
    if (!g_block) return;
    uint32_t head = C2S(C_BQ_HEAD);
    if (head == g_tail) return;
    zm_dflush();
    g_tail = bq_pump(g_block, g_tail, head);
}

void sbardq_publish(void) {
    if (!g_block) return;
    volatile uint32_t* s2c = &SND_REG(SND_S2C);
    bq_state s;
    bq_read(&s);
    if (!s.active) return; /* closed (a song took over): nothing more comes back */
    if (s.ev_count - g_ev > 64u) g_ev = s.ev_count - 64u; /* sid_live.zig EV_CAP: lapped, the newest */
    for (; g_ev != s.ev_count; g_ev++) {
        uint32_t ev[3];
        bq_event(g_ev, ev);
        bq_s2c_event(s2c, g_ev, ev);
    }
    bq_s2c_state(s2c, g_tail, &s, g_ev);
}
