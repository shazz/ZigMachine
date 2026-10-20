/* CHISEL (rtl/blitter's zm_blit, soc/zm_blit_soc.py) under hwBlit: bblit.c's steps 2-4, the
 * lazy wait (bchisel.h) and the QUEUE. Why each step is where it is:
 *
 * - GO, then one load of BLIT_WINDOW before anything else. GO is an IO store, so IOFence holds it
 *   until every posted DDR store is in DDR, and the tap sees it with `stores_idle` high and starts
 *   the op at once. The kick then copies the block into the engine's own bank (zm_blit_q.v, ~24
 *   clocks), and the window does not answer a read until that copy is over: the load stalls this
 *   in-order CPU until then, so no store of the cart's next op can reach the op just started.
 *   Registers stored while an op runs are no longer dropped (zm_blit_regs.v keeps two banks):
 *   there is nothing to replay.
 * - The lazy op's lines are worked out right after GO (bdi_plan_op): by the time it ends the cart
 *   may have written the next op's registers.
 * - A QUEUE (COMMAND 5) is always lazy: its ops' pixels are the cart's to wait for (the ZigOS
 *   queue's flush). Its range goes in the GO word; the firmware refuses a bad one as the machine
 *   does (CYCLES 0). Its lines are not worked out (a list may touch the whole plane): the sync
 *   drops the whole D$, once per list (write-through: nothing is lost). */
#include "bchisel.h"

#include "bdinval.h"
#include "board.h"
#include "vboard.h"
#include "zm_memmap.h"

uint8_t bchisel_pending;

#ifdef ZM_BLIT_HW
#define BLIT_BUSY (1u << 31)
#define BLIT_TIMEOUT 100000000u /* cycles: 1 s at 100 MHz; the biggest op is ~27 Mc a frame */
#ifndef BCHISEL_RD /* tests/test_chisel_async.py models CHISEL and its tap instead */
#define BCHISEL_RD(i) (((volatile uint32_t*)ZMB_WINDOW_ADDR)[i])
#define BCHISEL_GO(word) (*(volatile uint32_t*)ZMB_WINDOW_ADDR = (word)) /* COMMAND in [7:0] */
#endif

static volatile uint8_t* g_r; /* the lazy op's block */
static bdi_plan g_plan;       /* and its lines, taken at GO */

/* An op that never ends (a lost AXI response on HP2, a stuck sequencer) traps the cart instead of
 * hanging it: CART_STATE = 3 | 0xB1 << 24 | STATUS[15:0] << 8, read by the ARM (zm_blit_core dbg:
 * {op[2:0], st[2:0], px_idle, rd v/r, wr v/r, wr_pending, seq px_valid[3:0]}). */
#define HOT static inline __attribute__((always_inline))

HOT void wait_idle(void) {
    uint32_t t = board_cycles();
    while (BCHISEL_RD(0) & BLIT_BUSY) { /* the timeout every 64 polls: a tight poll sees BUSY fall sooner */
        for (int i = 0; i < 64 && (BCHISEL_RD(0) & BLIT_BUSY); i++) {
        }
        if (board_cycles() - t > BLIT_TIMEOUT) board_finish((int)(0xB10000u | (BCHISEL_RD(0) & 0xFFFFu)));
    }
}

/* The op is over: its lines out of the D$, CYCLES and STATUS where the machine leaves them (stored
 * only when they change: a run of equal ops leaves both as they were). */
HOT void finish(volatile uint8_t* r, const bdi_plan* p) {
    if (p->how == BDI_ALL) bdi_inval_all();
    else bdi_apply(p);
    volatile uint32_t* cyc = (volatile uint32_t*)(r + ZM_BLIT_CYCLES);
    uint32_t c = BCHISEL_RD(ZM_BLIT_CYCLES / 4 - ZM_OFF_BLIT / 4);
    if (*cyc != c) *cyc = c;
    if (r[ZM_BLIT_STATUS] != 0) r[ZM_BLIT_STATUS] = 0;
}

void bchisel_sync(void) {
    wait_idle();
    finish(g_r, &g_plan);
    bchisel_pending = 0;
}

/* The pending op's block and lines, once CHISEL has started it (the barrier load). */
HOT void pend(volatile uint8_t* r) {
    (void)BCHISEL_RD(0);
    g_r = r, bchisel_pending = 1;
}

/* GO, then either return (lazy: its lines planned now, while CHISEL runs) or wait and finish.
 * The plan of a waited op comes after the wait, as bdi_range always did: kept across the spin
 * its fields would push the hot path into saving registers to the stack, and every store is a
 * bus write (tests/test_blit_path.py holds hwBlit to a few a call). */
HOT void go(volatile uint8_t* r, uint8_t cmd) {
    BCHISEL_GO(cmd);
    if (r[ZM_BLIT_ASYNC]) { /* a load: it cannot race the start (the wait's first poll is the barrier) */
        pend(r);
        bdi_plan_op(r, cmd, &g_plan);
        return;
    }
    wait_idle();
    bdi_plan p;
    bdi_plan_op(r, cmd, &p);
    finish(r, &p);
}

/* A QUEUE: the list's range into the GO word, or refused as machine/blitter_queue.zig refuses it. */
static __attribute__((noinline)) void run_queue(volatile uint8_t* r) {
    uint32_t start = *(volatile uint16_t*)(r + ZM_BLIT_Q_START), count = *(volatile uint16_t*)(r + ZM_BLIT_Q_COUNT);
    if (count == 0 || start + count > ZM_BLIT_QUEUE_WORDS) {
        *(volatile uint32_t*)(r + ZM_BLIT_CYCLES) = 0;
        if (r[ZM_BLIT_STATUS] != 0) r[ZM_BLIT_STATUS] = 0;
        return;
    }
    BCHISEL_GO(ZM_BLIT_CMD_QUEUE | start << 8 | count << 17);
    pend(r);
    g_plan.how = BDI_ALL;
}

HOT void dispatch(volatile uint8_t* r) {
    uint8_t cmd = r[ZM_BLIT_COMMAND];
    if (cmd == ZM_BLIT_CMD_QUEUE) run_queue(r);
    else if (cmd) go(r, cmd); /* NOP: the machine leaves STATUS and CYCLES alone */
}

/* After a lazy op: out of line, so the common path below makes no call. */
static __attribute__((noinline)) void run_after_lazy(volatile uint8_t* r) {
    bchisel_sync();
    dispatch(r);
}

void bchisel_run(volatile uint8_t* r) {
    if (bchisel_pending) {
        run_after_lazy(r);
        return;
    }
    dispatch(r);
}
#else
void bchisel_sync(void) { bchisel_pending = 0; }
void bchisel_run(volatile uint8_t* r) { (void)r; }
#endif
