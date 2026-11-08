/* The SID on the sound side (SW_SID_ON_BARD, kestrel_sw_sid.h): the BARD queue's ring (decisions.md 2026-11-07
 * "The BARD queue"; libs/zig/bard.zig is the Zig side and the reference for this C copy of it: the same block,
 * the same rules). Included by kestrel_sw.c.
 *
 * Every write the 6502 makes to the SID ($D400-$D7FF, mirrors folded to $D400-$D418) is put on the ring after
 * the instruction that made it (kestrel_sw_clock.c sw_io_flush), stamped with the C64 cycle it happened at on
 * the cart's 44.1 kHz clock: t = cycle x 32 / SampleClockRatio, i.e. 2 output samples for every 22.05 kHz
 * "C64 sample" the cart runs (kestrel_sw.c sw_run_c64), so the stamps advance exactly as fast as the cart's
 * clock does (985248 cycles a second would drift 0.1 % against it: libcRSID's ratio is 714/16 cycles a sample).
 * The sound side (BARD on the board, the AudioWorklet on the page, host/audio_bardq.c natively) plays each write
 * on cRSID's raw SID at its sample, a lead behind the first batch. The cart never waits: a full ring drops the
 * write (counted in the header). Events coming back (resets, re-anchors, drops) are read and let go. */

#define SW_BQ_MAGIC 0x51424d5au                /* "ZMBQ" */
#define SW_BQ_CAP 256u                         /* commands (a power of two) */
#define SW_BQ_EV_CAP 16u
#define SW_BQ_LEAD 6144u                       /* ~139 ms: a 20 fps board frame and BARD's render, as BARD SID */
#define SW_BQ_SID_BASE 0xD400u
#define SW_BQ_OP_RESET 1u

enum { BQ_MAGIC, BQ_CAP, BQ_EV_CAP, BQ_LEAD, BQ_HEAD, BQ_TAIL, BQ_DROPPED, BQ_POS, BQ_ANCHORED, BQ_EV_HEAD, BQ_EV_TAIL, BQ_EV_LOST };
typedef struct { uint32_t t, addr, value, seq; } sw_bq_cmd;
static struct {
    uint32_t head[16];
    sw_bq_cmd cmds[SW_BQ_CAP];
    sw_bq_cmd events[SW_BQ_EV_CAP];
} sw_bq __attribute__((aligned(16)));
static int sw_bq_open_, sw_bq_tries;

__attribute__((import_module("env"), import_name("hostBardAttach"))) extern uint32_t hostBardAttach(uint32_t block, uint32_t lead);

static volatile uint32_t *sw_bq_word(int i) { return &sw_bq.head[i]; }

static int sw_bq_push(uint32_t t, uint32_t addr, uint32_t value)
{
    if (!sw_bq_open_) return 0;
    uint32_t head = *sw_bq_word(BQ_HEAD);
    if (head - *sw_bq_word(BQ_TAIL) >= SW_BQ_CAP) { *sw_bq_word(BQ_DROPPED) += 1; return 0; }
    volatile sw_bq_cmd *c = &sw_bq.cmds[head % SW_BQ_CAP];
    c->t = t; c->addr = addr; c->value = value;
    c->seq = head;                             /* last: the entry is whole when its seq is its index */
    *sw_bq_word(BQ_HEAD) = head + 1;
    return 1;
}

/* bard.open(): the header, every seq not its index, then the host's answer (0: no queue on this host). */
static int sw_bq_attach(void)
{
    memset(sw_bq.head, 0, sizeof sw_bq.head);
    for (unsigned i = 0; i < SW_BQ_CAP; i++) ((volatile sw_bq_cmd *)&sw_bq.cmds[i])->seq = 0xFFFFFFFFu;
    *sw_bq_word(BQ_CAP) = SW_BQ_CAP;
    *sw_bq_word(BQ_EV_CAP) = SW_BQ_EV_CAP;
    *sw_bq_word(BQ_LEAD) = SW_BQ_LEAD;
    *sw_bq_word(BQ_MAGIC) = SW_BQ_MAGIC;
    return hostBardAttach((uint32_t)(uintptr_t)&sw_bq, SW_BQ_LEAD) != 0;
}

/* The C64 cycle on the cart's 44.1 kHz clock (above). */
static uint32_t sw_bq_stamp(unsigned long long cycle)
{
    return (uint32_t)(cycle * 32u / cRSID_C64.SampleClockRatio);
}

/* A SID register write from the 6502 (register 0..0x1F of the chip; 0x19.. are read-only there). */
static void sw_sid_write(unsigned reg, unsigned value, unsigned long long cycle)
{
    if (reg <= 0x18) sw_bq_push(sw_bq_stamp(cycle), SW_BQ_SID_BASE + reg, value);
}

/* Once a frame: open the queue (the players may come up after the cart's boot: ask for a while, as BARD SID),
 * a fresh SID of the selected model, then the 25 registers as the C64 has them (the program set them before
 * the queue was open); and let the events go. */
static void sw_bq_frame(unsigned long long cycle)
{
    if (!sw_bq_open_ && sw_bq_tries < 120) {
        sw_bq_tries++;
        if ((sw_bq_open_ = sw_bq_attach())) {
            /* At C64 time 0 when the queue opens at once (the first frame, whatever its length: the stamps
             * then depend on the C64's time only), else now. */
            uint32_t t = sw_bq_tries == 1 ? 0 : sw_bq_stamp(cycle);
            sw_bq_push(t, SW_BQ_OP_RESET, cRSID.SelectedSIDmodel == 6581 ? 6581u : 8580u);
            for (unsigned r = 0; r <= 0x18; r++) sw_bq_push(t, SW_BQ_SID_BASE + r, cRSID_C64.IObankWR[0xD400 + r]);
            kestrel_log("sidwizard: the SID plays on the sound side (BARD queue)");
        }
    }
    if (sw_bq_open_) *sw_bq_word(BQ_EV_TAIL) = *sw_bq_word(BQ_EV_HEAD);
}

static void sw_bq_close(void) { if (sw_bq_open_) hostBardAttach(0, 0); sw_bq_open_ = 0; }
