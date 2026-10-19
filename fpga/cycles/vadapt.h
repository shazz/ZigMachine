/* Whether the dirty-line plan pays on this cart, measured (vplan.c).
 *
 * The plan costs CPU reads of every compared row; on a screen that changes
 * everywhere (or whose lines cannot be skipped) that is pure overhead, and on
 * the board it pushed carts over a vsync boundary (medium_overscan 60 -> 30 fps).
 * So the planes' phase of each frame is timed, and the plan only runs while it
 * makes that phase shorter than going without it:
 *
 *   OFF    no plan at all (every line composited, nothing compared), timed:
 *          the cost without the plan. After VA_OFF_FRAMES (VA_FIRST_OFF at boot), PROBE.
 *   PROBE  plan for VA_PROBE_FRAMES; the first two only fill the copies (a line
 *          can be skipped from the third), the rest are timed. ON if they took
 *          at most VA_GAIN_NUM / 16 of the OFF time, else OFF again.
 *   ON     plan, timed by windows of VA_ON_WINDOW frames; OFF as soon as a window
 *          is no faster than the OFF time.
 *
 * Portable (no clock of its own): the board feeds it cycles, the native proof a
 * cost model, and tests/test_vdirty.py checks that the bypass engages. */
#ifndef ZM_VADAPT_H
#define ZM_VADAPT_H

#include <stdint.h>

#define VA_FIRST_OFF 8
#define VA_OFF_FRAMES 120
#define VA_PROBE_FRAMES 4
#define VA_ON_WINDOW 8
#define VA_GAIN_NUM 15

enum { VA_OFF, VA_PROBE, VA_ON };

typedef struct {
    int mode;
    uint32_t n;                    /* frames in this mode (OFF, PROBE) or this window (ON) */
    uint64_t sum;                  /* the timed frames' cycles so far */
    uint32_t timed;                /* how many */
    uint32_t t_off;                /* mean cycles of the planes' phase without the plan */
    uint32_t switches, off_frames; /* stats: mode changes, frames run without the plan */
} va_state;

extern va_state va;

/* Before a frame: does it plan? */
int va_plans(void);
/* After it: the planes' phase took `cycles` (the swap wait left out). */
void va_frame(uint32_t cycles);

#endif
