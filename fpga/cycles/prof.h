/* Who a cycle belongs to. Force-included (-include) into the generated env.c,
 * where it defines the span hooks tools/host_gen.py leaves empty natively.
 *
 * A frame is split into spans, and each span's counters go to one owner:
 *   CART  cart.frame(), and the cart's HBL handlers (env.hblDispatch), which run
 *         INSIDE hwRenderPlane but are the cart's own code. The rom's code runs
 *         under them, as it will on the board's cart CPU.
 *   MACH  hwClear() and hwRenderPlane() minus the handlers: RTL on the board.
 *   BLIT  env.hwBlit, from the cart, the rom or a handler: RTL on the board too.
 *   IDLE  the driver: hashing, isPlaneEnabled, printing. Never reported.
 * Owners nest (MACH -> CART -> BLIT), so this is a stack. */
#ifndef ZM_PROF_H
#define ZM_PROF_H

#include <stdint.h>

#include "board.h"

enum { PROF_IDLE, PROF_CART, PROF_MACH, PROF_BLIT, PROF_CAL_OUT, PROF_CAL_IN, PROF_N };

typedef struct {
    uint32_t c[ZM_NCOUNT]; /* counter deltas charged to this owner; cleared every frame */
    uint32_t n_in;         /* spans of this owner entered */
    uint32_t n_out;        /* spans entered FROM this owner (it paid half a probe) */
} prof_acc;

extern prof_acc prof[PROF_N];
extern int prof_top; /* the owner being charged right now */

void prof_enter(int owner);
void prof_leave(void);
void prof_clear(void);
/* Times empty CAL_IN spans inside CAL_OUT: the probe's own cost, per span, as
 * seen from inside and from outside. tools/cycles_report.py subtracts it. */
void prof_calibrate(int spans);

#define HOST_SPAN_CART PROF_CART
#define HOST_SPAN_BLIT PROF_BLIT
#define HOST_SPAN_ENTER(owner) prof_enter(owner)
#define HOST_SPAN_LEAVE() prof_leave()

#endif
