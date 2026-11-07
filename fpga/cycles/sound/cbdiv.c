/* Counting divides for a snd-cbench bench (scbench.h): the core has no divider, so libgcc's divides
 * are a loop. These replace them (same results) and count the calls in cb_ndiv, so a bench can print
 * the runtime divides it made per frame. Link it in CBENCH_SRC (mp3bench.c carries its own copy). */
#include <stdint.h>

uint32_t cb_ndiv;

static uint32_t udiv(uint32_t a, uint32_t b, uint32_t *rem) {
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((a >> i) & 1u);
        if (r >= b) {
            r -= b;
            q |= 1u << i;
        }
    }
    cb_ndiv++;
    *rem = r;
    return q;
}

uint32_t __udivsi3(uint32_t a, uint32_t b);
uint32_t __umodsi3(uint32_t a, uint32_t b);
int32_t __divsi3(int32_t a, int32_t b);
int32_t __modsi3(int32_t a, int32_t b);

uint32_t __udivsi3(uint32_t a, uint32_t b) {
    uint32_t r;
    return udiv(a, b, &r);
}

uint32_t __umodsi3(uint32_t a, uint32_t b) {
    uint32_t r;
    udiv(a, b, &r);
    return r;
}

int32_t __divsi3(int32_t a, int32_t b) {
    uint32_t r, q = udiv(a < 0 ? -(uint32_t)a : (uint32_t)a, b < 0 ? -(uint32_t)b : (uint32_t)b, &r);
    return (a < 0) != (b < 0) ? -(int32_t)q : (int32_t)q;
}

int32_t __modsi3(int32_t a, int32_t b) {
    uint32_t r;
    udiv(a < 0 ? -(uint32_t)a : (uint32_t)a, b < 0 ? -(uint32_t)b : (uint32_t)b, &r);
    return a < 0 ? -(int32_t)r : (int32_t)r;
}
