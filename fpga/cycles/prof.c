#include "prof.h"

#include <string.h>

#define PROF_DEPTH 32

prof_acc prof[PROF_N];
int prof_top = PROF_IDLE;
static int g_stack[PROF_DEPTH];
static int g_sp;
static uint32_t g_last[ZM_NCOUNT];

/* Everything since the last probe goes to whoever was on top. Counters are
 * mod 2^32 and a span is far shorter than 2^32 cycles, so the unsigned
 * difference is exact. */
static inline void charge(void) {
    uint32_t now[ZM_NCOUNT];
    board_counters(now);
    prof_acc* a = &prof[prof_top];
    for (int i = 0; i < ZM_NCOUNT; i++) {
        a->c[i] += now[i] - g_last[i];
        g_last[i] = now[i];
    }
}

__attribute__((noinline)) void prof_enter(int owner) {
    charge();
    prof[prof_top].n_out++;
    prof[owner].n_in++;
    if (g_sp + 1 >= PROF_DEPTH) board_finish(4); /* deeper than any HBL nesting can go */
    g_stack[++g_sp] = prof_top;
    prof_top = owner;
}

__attribute__((noinline)) void prof_leave(void) {
    charge();
    prof_top = g_stack[g_sp--];
}

void prof_clear(void) {
    memset(prof, 0, sizeof prof);
    board_counters(g_last);
}

void prof_calibrate(int spans) {
    prof_clear();
    prof_enter(PROF_CAL_OUT);
    for (int i = 0; i < spans; i++) {
        prof_enter(PROF_CAL_IN);
        prof_leave();
    }
    prof_leave();
}
