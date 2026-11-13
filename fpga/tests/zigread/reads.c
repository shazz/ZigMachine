/* tests/test_ziggy_reads.py: the bench cart's RAM loops (apps/c/bench/kestrel/k_mem.c: 8x unrolled
 * long-word read / write / copy) plus a line-miss and a random-line probe, on the board's read path
 * (tests/zigread_top.py). Each kernel reports three words: its id, its cycles, a checksum of what it
 * read (equal on every bridge variant: a prefetch that serves a stale line changes it). */
#include <stdint.h>

#define DEV ((volatile uint32_t *)0xf0000000u)
#define BUF ((uint32_t *)0x40100000u) /* 1 MiB in: above the code and the stack */
#define K4 1024u                       /* words */
#define K64 (16u * 1024u)
#define K256 (64u * 1024u)

typedef uint32_t u32;

#define BARRIER() __asm__ volatile("" ::: "memory")
static u32 now(void) { BARRIER(); u32 t = DEV[1]; BARRIER(); return t; }
static void report(u32 id, u32 cycles, u32 sum) { DEV[2] = id, DEV[2] = cycles, DEV[2] = sum; }

static void wr(u32 *p, u32 n, u32 v) {
    for (u32 i = 0; i < n; i += 8) { p[i]=v; p[i+1]=v+1; p[i+2]=v+2; p[i+3]=v+3; p[i+4]=v+4; p[i+5]=v+5; p[i+6]=v+6; p[i+7]=v+7; }
}
static u32 rd(const u32 *p, u32 n) {
    u32 s = 0;
    for (u32 i = 0; i < n; i += 8) { s+=p[i]; s+=p[i+1]; s+=p[i+2]; s+=p[i+3]; s+=p[i+4]; s+=p[i+5]; s+=p[i+6]; s+=p[i+7]; }
    return s;
}
static void cp(u32 *d, const u32 *s, u32 n) {
    for (u32 i = 0; i < n; i += 8) { d[i]=s[i]; d[i+1]=s[i+1]; d[i+2]=s[i+2]; d[i+3]=s[i+3]; d[i+4]=s[i+4]; d[i+5]=s[i+5]; d[i+6]=s[i+6]; d[i+7]=s[i+7]; }
}
static u32 line_miss(const u32 *p, u32 n) { /* one load a line: the bare miss (BENCH_REPORTS ld.miss) */
    u32 s = 0;
    for (u32 i = 0; i < n; i += 8) s += p[i];
    return s;
}
static u32 random_lines(const u32 *p, u32 lines, u32 loads) { /* a texture's random reads */
    u32 s = 0, x = 12345;
    for (u32 i = 0; i < loads; i++) { x = x * 1103515245u + 12345u; s += p[((x >> 8) % lines) * 8]; }
    return s;
}

int main(void) {
    u32 *a = BUF, *b = BUF + K256, t, s;
    t = now(); wr(a, K256, 0x1000); report(1, now() - t, 0);           /* write 256 KB */
    rd(a, K4); t = now(); s = 0;                                       /* read 4 KB, warm, x16 */
    for (int r = 0; r < 16; r++) { s += rd(a, K4); BARRIER(); }
    report(2, now() - t, s);
    t = now(); s = rd(a + K64, K256 - K64); report(3, now() - t, s);   /* read 192 KB, cold */
    t = now(); s = line_miss(b - K64, K64); report(4, now() - t, s);   /* 2048 bare line misses */
    t = now(); cp(b, a, K64); t = now() - t; report(5, t, rd(b, K64));  /* copy 64 KB */
    t = now(); s = random_lines(a, K256 / 8, 2048); report(6, now() - t, s); /* 2048 random lines */
    /* Coherence: read line L (the bridge prefetches L+1), wait until that prefetch is in, store to
     * L+1, then the stream reaches L+1: a prefetch that ignores the store serves the old word. */
    s = 0;
    for (u32 i = 0; i < K4; i += 8) {
        s += a[i];
        __asm__ volatile(".rept 60\n nop\n .endr" ::: "memory");
        a[i + 8] = i;
    }
    report(7, 0, s + rd(a, K4 + 8));
    return 0;
}
