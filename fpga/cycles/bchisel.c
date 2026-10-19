/* CHISEL (rtl/blitter's zm_blit, soc/zm_blit_soc.py) under hwBlit: bblit.c's steps 2-4, and the
 * lazy wait (bchisel.h). Why each step is where it is:
 *
 * - GO, then one load of BLIT_WINDOW before anything else. GO is an IO store, so IOFence holds it
 *   until every posted DDR store is in DDR, and the tap sees it with `stores_idle` high and starts
 *   the op at once. A DDR store issued right behind GO could make the tap HOLD the start (its
 *   `fire = held & stores_idle`), and a register store reaching the tap meanwhile would be taken
 *   into the op about to run. The load stalls this in-order CPU until the tap has decided.
 * - The lazy op's lines are worked out right after GO (bdi_plan_op): by the time it ends the cart
 *   may have written the next op's registers.
 * - Registers stored while an op runs are DROPPED (zm_blit_regs.v: no write while BUSY); memory has
 *   them, as the machine's does. So after a lazy op every word of the block is stored back through
 *   the tap (replay): the block in zm_blit is then memory's again, whichever stores were lost. */
#include "bchisel.h"

#include "bdinval.h"
#include "board.h"
#include "vboard.h"
#include "zm_memmap.h"

uint8_t bchisel_pending;

#ifdef ZM_BLIT_HW
#define BLIT_BUSY (1u << 31)
#define BLIT_TIMEOUT 100000000u /* cycles: 1 s at 100 MHz; the biggest op is ~27 Mc a frame */
#define BLIT_WORDS 24u          /* the block's words zm_blit stores (zm_blit_soc.py REG_WORDS) */
#ifndef BCHISEL_RD /* tests/test_chisel_async.py models CHISEL and its tap instead */
#define BCHISEL_RD(i) (((volatile uint32_t*)ZMB_WINDOW_ADDR)[i])
#define BCHISEL_GO(cmd) (*(volatile uint8_t*)ZMB_WINDOW_ADDR = (cmd))
#define BCHISEL_PUT(w, i) ((w)[i] = (w)[i]) /* a store of memory's own word: the tap takes it */
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

static void replay(volatile uint8_t* r) {
    volatile uint32_t* w = (volatile uint32_t*)(r + ZM_OFF_BLIT);
    for (uint32_t i = 0; i < BLIT_WORDS; i++) BCHISEL_PUT(w, i); /* word 0: the tap never takes COMMAND */
}

void bchisel_sync(void) {
    wait_idle();
    finish(g_r, &g_plan);
    replay(g_r);
    bchisel_pending = 0;
}

/* GO, then either return (lazy: its lines planned now, while CHISEL runs) or wait and finish.
 * The plan of a waited op comes after the wait, as bdi_range always did: kept across the spin
 * its fields would push the hot path into saving registers to the stack, and every store is a
 * bus write (tests/test_blit_path.py holds hwBlit to a few a call). */
HOT void go(volatile uint8_t* r, uint8_t cmd) {
    BCHISEL_GO(cmd);
    if (r[ZM_BLIT_ASYNC]) { /* a load: it cannot race the start (the wait's first poll is the barrier) */
        (void)BCHISEL_RD(0); /* the tap has started the op before any later store reaches it (above) */
        bdi_plan_op(r, cmd, &g_plan);
        g_r = r, bchisel_pending = 1;
        return;
    }
    wait_idle();
    bdi_plan p;
    bdi_plan_op(r, cmd, &p);
    finish(r, &p);
}

/* After a lazy op: out of line, so the common path below makes no call. */
static __attribute__((noinline)) void run_after_lazy(volatile uint8_t* r) {
    bchisel_sync();
    uint8_t cmd = r[ZM_BLIT_COMMAND];
    if (cmd) go(r, cmd); /* NOP: the machine leaves STATUS and CYCLES alone */
}

void bchisel_run(volatile uint8_t* r) {
    if (bchisel_pending) {
        run_after_lazy(r);
        return;
    }
    uint8_t cmd = r[ZM_BLIT_COMMAND];
    if (cmd) go(r, cmd); /* NOP: the machine leaves STATUS and CYCLES alone */
}
#else
void bchisel_sync(void) { bchisel_pending = 0; }
void bchisel_run(volatile uint8_t* r) { (void)r; }
#endif
