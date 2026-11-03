/* malloc/free/calloc/realloc for pt2-clone over the machine's RAM arena.
 *
 * wasi-libc's malloc grows memory with memory.grow; the cart's memory is fixed and shared with the
 * machine, so it would fail (or worse). Defining these here keeps libc's malloc out of the link.
 * One arena is taken from hwRamAlloc at the first call; blocks are first-fit with boundary sizes,
 * and free() merges with the next free block (pt2 frees rarely: samples, modules, temp buffers). */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include "../../../c/zigmachine_mem.h" /* apps/ports/kestrel_sdl2/src -> apps/c */

#define ALIGN 16u
#define HDR ALIGN                 /* header: size (bytes incl. header) | used bit, padded to 16 */
#define RESERVE (64u * 1024u)     /* left in the machine arena for anything else */

static uint8_t *heap_lo, *heap_hi;
/* KESTREL_HEAP_ROVER (opt-in, klystrack): no free block starts below `rover`, so malloc's first-fit scan starts
 * there instead of at heap_lo. Same block chosen as without it (first fit), but a boot that makes thousands of
 * small allocations stops walking every used block each time (klystrack: 404k block visits, ~23 Mc at boot). */
#ifdef KESTREL_HEAP_ROVER
static uint8_t *rover;
#define ROVER_START (rover ? rover : heap_lo)
#define ROVER_SET(p) (rover = (p))
#else
#define ROVER_START heap_lo
#define ROVER_SET(p) ((void)0)
#endif
void kestrel_log(const char *m);
int snprintf(char *, size_t, const char *, ...);
static size_t bsz_(uint8_t *b) { return *(size_t *)b & ~(size_t)1; }
static void oom(size_t n)
{
    size_t inuse = 0, big = 0;
    for (uint8_t *b = heap_lo; b && b < heap_hi; b += bsz_(b)) { if (*(size_t *)b & 1) inuse += bsz_(b); else if (bsz_(b) > big) big = bsz_(b); }
    char m[128], w[40] = "heap";
    if (n) snprintf(w, sizeof w, "heap: malloc(%u) failed", (unsigned)n);
    snprintf(m, sizeof m, "%s: heap %u, in use %u, largest free %u", w, (unsigned)(heap_hi - heap_lo), (unsigned)inuse, (unsigned)big);
    kestrel_log(m);
}

static inline size_t *hdr(uint8_t *b) { return (size_t *)b; }
static inline size_t bsize(uint8_t *b) { return *hdr(b) & ~(size_t)1; }
static inline int used(uint8_t *b) { return (int)(*hdr(b) & 1); }

static int heap_init(void)
{
    if (heap_lo) return 1;
    unsigned avail = hwRamFree();
    if (avail <= RESERVE + 4 * ALIGN) return 0;
    unsigned bytes = (avail - RESERVE) & ~(ALIGN - 1);
    heap_lo = zm_alloc(bytes, ALIGN);
    if (!heap_lo) return 0;
    heap_hi = heap_lo + bytes;
    *hdr(heap_lo) = bytes;        /* one free block */
    return 1;
}

static void merge_next(uint8_t *b)
{
    uint8_t *n = b + bsize(b);
    while (n < heap_hi && !used(n)) { *hdr(b) = bsize(b) + bsize(n); n = b + bsize(b); }
}

void *malloc(size_t n)
{
#ifdef HEAP_TRACE
    if (n >= 16384) { char b[64]; snprintf(b, sizeof b, "malloc %u", (unsigned)n); kestrel_log(b); }
#endif
    if (!heap_init() || n > (size_t)(heap_hi - heap_lo)) { oom(n); errno = ENOMEM; return NULL; }
    size_t need = (n + HDR + ALIGN - 1) & ~(size_t)(ALIGN - 1);
    uint8_t *first_free = NULL;
    for (uint8_t *b = ROVER_START; b < heap_hi; b += bsize(b)) {
        if (used(b)) continue;
        merge_next(b);
        if (!first_free) first_free = b;
        size_t sz = bsize(b);
        if (sz < need) continue;
        if (sz - need >= HDR + ALIGN) { *hdr(b + need) = sz - need; sz = need; }
        *hdr(b) = sz | 1;
        ROVER_SET(b == first_free ? b + sz : first_free);
        return b + HDR;
    }
    ROVER_SET(first_free ? first_free : heap_hi);
    oom(n);
    errno = ENOMEM;
    return NULL;
}

void free(void *p)
{
    if (!p) return;
    uint8_t *b = (uint8_t *)p - HDR;
    *hdr(b) = bsize(b);
    merge_next(b);
#ifdef KESTREL_HEAP_ROVER
    if (b < ROVER_START) rover = b;
#endif
}

void *calloc(size_t a, size_t b)
{
    if (b && a > SIZE_MAX / b) { errno = ENOMEM; return NULL; }
    void *p = malloc(a * b);
    if (p) memset(p, 0, a * b);
    return p;
}

void *realloc(void *p, size_t n)
{
    if (!p) return malloc(n);
    if (n == 0) { free(p); return NULL; }
    uint8_t *b = (uint8_t *)p - HDR;
    size_t have = bsize(b) - HDR;
    if (n <= have) return p;
    merge_next(b);                                 /* grow in place when the next block is free */
    size_t need = (n + HDR + ALIGN - 1) & ~(size_t)(ALIGN - 1);
    if (bsize(b) >= need) {
        size_t sz = bsize(b);
        if (sz - need >= HDR + ALIGN) { *hdr(b + need) = sz - need; sz = need; }
        *hdr(b) = sz | 1;
#ifdef KESTREL_HEAP_ROVER
        if (rover > b && rover < b + sz) rover = b + sz;   /* the grown block swallowed the rover's free block */
#endif
        return p;
    }
    void *q = malloc(n);
    if (!q) return NULL;
    memcpy(q, p, have);
    free(p);
    return q;
}

/* pt2 needs no alignment above 16; refuse larger rather than return a misaligned block. */
void *aligned_alloc(size_t al, size_t n) { if (al > ALIGN) { errno = EINVAL; return NULL; } return malloc(n); }
int posix_memalign(void **out, size_t al, size_t n)
{
    if (al > ALIGN) return EINVAL;
    *out = malloc(n);
    return *out ? 0 : ENOMEM;
}

void kestrel_heap_report(void) { oom(0); }   /* n = 0: the report, not a failure */
