/* libc-lite for the benchmark cart: string.h basics, a bump malloc, the clock, and a printf that captures
 * into rt_out (the harness and the checks read it; nothing is drawn from it). Own code, CC0.
 * memcpy/memset/memcmp and sin/cos/exp/log come from the toolchain's compiler_rt, not from here. */
#include <stdarg.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <sys/times.h>
#include "bench.h"

__attribute__((import_module("env"), import_name("hostMicros"))) extern u32 hostMicros(void);
u32 bench_now(void) { return hostMicros(); }

/* Any non-zero reading means a clock: an honest counter can read 0 once, never always. */
int bench_has_clock(void) {
    for (int i = 0; i < 64; i++) if (hostMicros() != 0) return 1;
    return 0;
}
long time(long *t) { long v = (long)hostMicros(); if (t) *t = v; return v; }

int times(struct tms *t) { clock_t v = (clock_t)hostMicros(); t->tms_utime = v; t->tms_stime = t->tms_cutime = t->tms_cstime = 0; return (int)v; }

size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)) {} return r; }
int strcmp(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return (unsigned char)*a - (unsigned char)*b; }
int strncmp(const char *a, const char *b, size_t n) {
    for (; n; n--, a++, b++) { if (*a != *b || !*a) return (unsigned char)*a - (unsigned char)*b; }
    return 0;
}
void *memmove(void *d, const void *s, size_t n) {
    unsigned char *dd = d; const unsigned char *ss = s;
    if (dd < ss) while (n--) *dd++ = *ss++; else { dd += n; ss += n; while (n--) *--dd = *--ss; }
    return d;
}
int atoi(const char *s) { return (int)atol(s); }
long atol(const char *s) {
    long v = 0; int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
    return neg ? -v : v;
}

/* A bump allocator: Dhrystone mallocs two records per run, CoreMark nothing (MEM_STATIC). */
static unsigned char heap[2048] __attribute__((aligned(8)));
static size_t heap_used;
void rt_heap_reset(void) { heap_used = 0; }
void *malloc(size_t n) {
    n = (n + 7) & ~(size_t)7;
    if (heap_used + n > sizeof heap) return 0;
    void *p = heap + heap_used; heap_used += n; return p;
}
void free(void *p) { (void)p; }

char rt_out[2048];
static size_t out_len;
void rt_out_reset(void) { out_len = 0; rt_out[0] = 0; }

typedef struct { char *b; size_t cap, n; } sink;
static void put(sink *s, char c) { if (s->n + 1 < s->cap) s->b[s->n] = c; s->n++; }

static void put_pad(sink *s, const char *d, int len, int width, int left, char pad) {
    if (!left) for (int i = len; i < width; i++) put(s, pad);
    for (int i = 0; i < len; i++) put(s, d[i]);
    if (left) for (int i = len; i < width; i++) put(s, ' ');
}

static int fmt_uint(char *t, u64 v, unsigned base, int upper) {
    char r[24]; int n = 0;
    do { unsigned d = (unsigned)(v % base); r[n++] = (char)(d < 10 ? '0' + d : (upper ? 'A' : 'a') + d - 10); v /= base; } while (v);
    for (int i = 0; i < n; i++) t[i] = r[n - 1 - i];
    return n;
}

static int fmt_fixed(char *t, double v, int prec) {
    int n = 0;
    if (v < 0) { t[n++] = '-'; v = -v; }
    if (v >= 1.8e19) { t[n++] = 'i'; t[n++] = 'n'; t[n++] = 'f'; return n; }
    double scale = 1; for (int i = 0; i < prec; i++) scale *= 10;
    u64 all = (u64)(v * scale + 0.5), ip = all / (u64)scale, fp = all % (u64)scale;
    n += fmt_uint(t + n, ip, 10, 0);
    if (prec) {
        t[n++] = '.';
        char f[24]; int fl = fmt_uint(f, fp, 10, 0);
        for (int i = fl; i < prec; i++) t[n++] = '0';
        for (int i = 0; i < fl; i++) t[n++] = f[i];
    }
    return n;
}

typedef struct { int left, zero, width, prec, lng; } spec;

static void do_conv(sink *s, char c, const spec *sp, va_list *ap) {
    char t[48]; const char *d = t; int len = 0; char pad = sp->zero && !sp->left ? '0' : ' ';
    if (c == 'd' || c == 'i') {
        long v = sp->lng ? va_arg(*ap, long) : va_arg(*ap, int);
        if (v < 0) { t[len++] = '-'; v = -v; }
        len += fmt_uint(t + len, (u64)v, 10, 0);
    } else if (c == 'u' || c == 'x' || c == 'X') {
        u64 v = sp->lng ? va_arg(*ap, unsigned long) : va_arg(*ap, unsigned);
        len = fmt_uint(t, v, c == 'u' ? 10 : 16, c == 'X');
    } else if (c == 'c') { t[len++] = (char)va_arg(*ap, int);
    } else if (c == 's') { d = va_arg(*ap, const char *); if (!d) d = "(null)"; len = (int)strlen(d);
        if (sp->prec >= 0 && len > sp->prec) len = sp->prec; pad = ' ';
    } else if (c == 'f') { len = fmt_fixed(t, va_arg(*ap, double), sp->prec < 0 ? 6 : sp->prec);
    } else { t[len++] = c; }
    put_pad(s, d, len, sp->width, sp->left, pad);
}

int vsnprintf(char *buf, size_t cap, const char *f, va_list ap) {
    sink s = { buf, cap, 0 };
    va_list ap2; va_copy(ap2, ap);
    for (; *f; f++) {
        if (*f != '%') { put(&s, *f); continue; }
        spec sp = { 0, 0, 0, -1, 0 };
        for (f++; *f == '-' || *f == '0'; f++) { if (*f == '-') sp.left = 1; else sp.zero = 1; }
        while (*f >= '0' && *f <= '9') sp.width = sp.width * 10 + (*f++ - '0');
        if (*f == '.') { f++; sp.prec = 0; while (*f >= '0' && *f <= '9') sp.prec = sp.prec * 10 + (*f++ - '0'); }
        if (*f == 'l') { sp.lng = 1; f++; }
        if (!*f) break;
        if (*f == '%') put(&s, '%'); else do_conv(&s, *f, &sp, &ap2);
    }
    va_end(ap2);
    if (cap) s.b[s.n < cap ? s.n : cap - 1] = 0;
    return (int)s.n;
}

int snprintf(char *b, size_t cap, const char *f, ...) {
    va_list ap; va_start(ap, f); int n = vsnprintf(b, cap, f, ap); va_end(ap); return n;
}

static int out_v(const char *f, va_list ap) {
    int n = vsnprintf(rt_out + out_len, sizeof rt_out - out_len, f, ap);
    out_len += (size_t)n < sizeof rt_out - out_len ? (size_t)n : sizeof rt_out - out_len - 1;
    return n;
}
int printf(const char *f, ...) { va_list ap; va_start(ap, f); int n = out_v(f, ap); va_end(ap); return n; }
int fprintf(void *fp, const char *f, ...) { (void)fp; va_list ap; va_start(ap, f); int n = out_v(f, ap); va_end(ap); return n; }
char *fgets(char *b, int n, void *fp) { (void)b; (void)n; (void)fp; return 0; }

int rt_has_line(const char *needle) {
    size_t nl = strlen(needle);
    for (size_t i = 0; rt_out[i]; i++) if (!strncmp(rt_out + i, needle, nl)) return 1;
    return 0;
}
