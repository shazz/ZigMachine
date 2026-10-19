/* See vadapt.h. */
#include "vadapt.h"

va_state va = {VA_OFF, 0, 0, 0, 0, 0, 0};

static void enter(int mode) {
    va.mode = mode, va.n = 0, va.sum = 0, va.timed = 0;
    va.switches++;
}

static uint32_t mean(void) { return va.timed ? (uint32_t)(va.sum / va.timed) : 0; }

int va_plans(void) { return va.mode != VA_OFF; }

/* OFF: the last VA_ON_WINDOW frames make the cost without the plan. */
static void off_frame(uint32_t cycles) {
    va.off_frames++;
    if (va.timed == VA_ON_WINDOW) va.sum -= va.sum / VA_ON_WINDOW, va.timed--;
    va.sum += cycles, va.timed++;
    va.t_off = mean();
    uint32_t wait = va.switches ? VA_OFF_FRAMES : VA_FIRST_OFF;
    if (++va.n >= wait) enter(VA_PROBE);
}

/* Planning made the phase at least (16 - VA_GAIN_NUM) / 16 shorter. */
static int pays(uint32_t t_on) { return (uint64_t)t_on * 16 <= (uint64_t)va.t_off * VA_GAIN_NUM; }

void va_frame(uint32_t cycles) {
    if (va.mode == VA_OFF) return off_frame(cycles);
    if (va.mode == VA_PROBE) {
        if (++va.n > 2) va.sum += cycles, va.timed++; /* frames 1-2 fill the copies: nothing is skipped yet */
        if (va.n < VA_PROBE_FRAMES) return;
        int on = pays(mean());
        uint32_t t_off = va.t_off;
        enter(on ? VA_ON : VA_OFF);
        va.t_off = t_off;
        return;
    }
    va.sum += cycles, va.timed++;
    if (++va.n < VA_ON_WINDOW) return;
    int keep = mean() < va.t_off;
    uint32_t t_off = va.t_off;
    enter(keep ? VA_ON : VA_OFF);
    va.t_off = t_off;
    if (keep) va.switches--; /* a new window, not a change */
}
