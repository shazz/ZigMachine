/* cycles/zm_string.c against the host libc: memset, memcpy and memmove (both overlap
 * directions) over every alignment, lengths 0..70 and up to 2000, 200,000 random cases.
 * The file is included with its symbols renamed, so the host's own libc stays the oracle. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define memset zm_memset
#define memcpy zm_memcpy
#define memmove zm_memmove
#include "../../cycles/zm_string.c"
#undef memset
#undef memcpy
#undef memmove

static uint8_t ref[4096], got[4096];
static unsigned rng = 12345;
static unsigned rnd(void) { rng = rng * 1103515245u + 12345u; return rng >> 8; }

static void fill(void) {
    for (int i = 0; i < 4096; i++) ref[i] = got[i] = (uint8_t)rnd();
}

static int one_case(int it) {
    fill();
    size_t n = (it % 3 == 0) ? rnd() % 2000 : rnd() % 71;
    size_t d = rnd() % 1024, s = rnd() % 1024;
    int kind = rnd() % 3;
    if (kind == 1 && 2048 + s + n > sizeof ref) n = sizeof ref - 2048 - s; /* the source stays inside */
    if (kind == 1 && d + n > 2048 + s) kind = 2; /* memcpy's ranges may not overlap: move instead */
    if (kind == 0) {
        int v = (int)(rnd() & 0xff);
        memset(ref + d, v, n);
        zm_memset(got + d, v, n);
    } else if (kind == 1) { /* non-overlapping: the source in the upper half */
        memcpy(ref + d, ref + 2048 + s, n);
        zm_memcpy(got + d, got + 2048 + s, n);
    } else {
        memmove(ref + d, ref + s, n);
        zm_memmove(got + d, got + s, n);
    }
    if (memcmp(ref, got, 4096) == 0) return 0;
    printf("FAIL kind %d d %zu s %zu n %zu\n", kind, d, s, n);
    return 1;
}

int main(void) {
    long fails = 0;
    for (int it = 0; it < 200000; it++) fails += one_case(it);
    printf("%s (%ld fails)\n", fails ? "BAD" : "OK", fails);
    return fails != 0;
}
