/* snd-bench SND_BARDQ=1: BARD's load for SID live, the BARD queue's raw-SID mode (host/bardq.h). No cart:
 * the commands are BARD SID's (apps/bard_queue_check.mjs --dump: {t, addr, value, 0} as the page's loader
 * posted them), linked in as zm_bardq_log (cycles/sound.mk makes the C array). A ring in BARD's own memory
 * stands for the cart's: before each frame the commands a cart would have written by then (stamps up to a
 * lead past the frame's end) go in, and the frame is timed with the pump, as the play image runs it. */
#include "../../host/bardq.h"
#include "sbardq.h"

extern const uint32_t zm_bardq_log[];
extern const uint32_t zm_bardq_log_words;

#define CAP 1024u
#define EV_CAP 16u
#define LEAD 6144u /* apps/zig/scenes/bard_sid.zig LEAD */
#define FRAME 735u

static uint32_t g_block[BQ_HEAD_WORDS + 4u * (CAP + EV_CAP)];
static uint32_t g_at, g_head, g_tail;

void bq_bench_start(void) {
    g_block[BQ_MAGIC_W] = BQ_MAGIC;
    g_block[BQ_CAP_W] = CAP;
    g_block[BQ_EV_CAP_W] = EV_CAP;
    g_block[BQ_LEAD_W] = LEAD;
    bq_open(LEAD);
}

/* Frame `f`'s commands into the ring, then into the players: what BARD's loop does when ZIGGY's head moves. */
uint32_t bq_bench_frame(uint32_t f) {
    uint32_t end = (f + 1u) * FRAME + LEAD, n = zm_bardq_log_words / 4u, put = 0;
    for (; g_at < n && zm_bardq_log[4u * g_at] < end && g_head - g_tail < CAP; g_at++, g_head++, put++) {
        uint32_t* e = g_block + BQ_HEAD_WORDS + 4u * (g_head % CAP);
        e[0] = zm_bardq_log[4u * g_at];
        e[1] = zm_bardq_log[4u * g_at + 1u];
        e[2] = zm_bardq_log[4u * g_at + 2u];
        e[3] = g_head;
    }
    g_tail = bq_pump(g_block, g_tail, g_head);
    return put;
}
