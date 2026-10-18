/* See vdrows.h. */
#include "vdrows.h"

#include <string.h>

#include "zm_memmap.h"

#define QMAX (ZM_NB_PLANES * ZM_RASTER_HEIGHT) /* one row a plane a line: a frame's worth */

typedef struct {
    uint8_t* copy;
    const uint8_t* src;
    uint32_t n;
} pending;

static pending g_q[QMAX];
static int g_head, g_tail;

/* The first word (in words) where src and copy differ, n / 4 if none. Word-aligned rows go
 * 32 bytes at a time into registers: the board's D$ is direct-mapped, and the source and its
 * copy can share a set, so word by word they would evict each other on every load. */
static uint32_t first_diff(const uint32_t* a, const uint32_t* b, uint32_t nw) {
    uint32_t i = 0;
    for (; i + 8 <= nw; i += 8) {
        uint32_t a0 = a[i], a1 = a[i + 1], a2 = a[i + 2], a3 = a[i + 3];
        uint32_t a4 = a[i + 4], a5 = a[i + 5], a6 = a[i + 6], a7 = a[i + 7];
        __asm__ volatile("" ::: "memory"); /* the source's block is in registers before its copy is read */
        if ((a0 ^ b[i]) | (a1 ^ b[i + 1]) | (a2 ^ b[i + 2]) | (a3 ^ b[i + 3]) | (a4 ^ b[i + 4]) | (a5 ^ b[i + 5]) |
            (a6 ^ b[i + 6]) | (a7 ^ b[i + 7]))
            break;
    }
    for (; i < nw && a[i] == b[i]; i++) {
    }
    return i;
}

/* The byte from which copy and src differ, n if they do not. */
static uint32_t diff_at(const uint8_t* copy, const uint8_t* src, uint32_t n) {
    if (((uintptr_t)src | (uintptr_t)copy | n) & 3) return memcmp(copy, src, n) ? 0 : n;
    return 4 * first_diff((const uint32_t*)src, (const uint32_t*)copy, n / 4);
}

int vdr_cmpcpy(uint8_t* copy, const uint8_t* src, uint32_t n) {
    uint32_t i = diff_at(copy, src, n);
    if (i == n) return 0;
    memcpy(copy + i, src + i, n - i);
    return 1;
}

void vdr_queue(uint8_t* copy, const uint8_t* src, uint32_t n) {
    if (g_tail == QMAX) vdr_copy(-1); /* full: nothing is lost, it is only done now (and the queue is empty) */
    g_q[g_tail++] = (pending){copy, src, n};
}

int vdr_differ(uint8_t* copy, const uint8_t* src, uint32_t n) {
    uint32_t i = diff_at(copy, src, n);
    if (i == n) return 0;
    vdr_queue(copy + i, src + i, n - i);
    return 1;
}

int vdr_copy(int n) {
    for (; g_head < g_tail && n != 0; g_head++, n--) memcpy(g_q[g_head].copy, g_q[g_head].src, g_q[g_head].n);
    if (g_head == g_tail) g_head = g_tail = 0;
    return g_tail - g_head;
}
