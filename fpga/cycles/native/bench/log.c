/* The bench's report: one ZMBENCH line a test, as text in a buffer the ARM can read.
 *
 * On the board ZIGGY has no console (cycles/bboard.c prints nothing: the JTAG UART has no
 * reader), so the lines go to memory. The buffer is this file's only .bss object and the
 * build links this file first, so it sits at the cart's __cart_bss_start: a fixed address,
 * which the cart header gives (bss_start, word 3 of the image at CART_IMG_AT). The ARM maps
 * the cart window through /dev/mem as glass does, reads bss_start, and finds the log there
 * (fpga/tools/bench_collect.py). test_native_bench.py holds the placement.
 *
 *   ZMBENCH name=<test> size=<bytes> cyc=<min> med=<median> ops=<n> dwait=<n> dwr=<n>
 *
 * cyc and med are the body's cycles, the calibration (an empty body) subtracted; dwait and dwr
 * are the data-bus wait cycles and writes of the fastest repeat (soc/zm_cycles.py). */
#include "bench.h"

#define LOG_MAGIC 0x4c424d5au /* "ZMBL" */
#define LOG_BYTES 16384u

/* Read by the ARM: keep the layout (bench_collect.py LOG_*). */
struct zmb_log {
    uint32_t magic;
    uint32_t done;  /* 1 once every test has run */
    uint32_t len;   /* bytes of text */
    uint32_t lines;
    char text[LOG_BYTES];
};
struct zmb_log zmb_log; /* .bss: first in the image's .bss (native.mk links log.c first) */

char* fmt_str(char* p, const char* s) {
    while (*s) *p++ = *s++;
    return p;
}

char* fmt_u32(char* p, uint32_t v) {
    char tmp[10];
    int n = 0;
    do tmp[n++] = (char)('0' + v % 10u), v /= 10u;
    while (v);
    while (n) *p++ = tmp[--n];
    return p;
}

char* fmt_fixed1(char* p, uint32_t num, uint32_t den) {
    if (!den) return fmt_str(p, "-");
    uint64_t t = ((uint64_t)num * 10u + den / 2u) / den;
    p = fmt_u32(p, (uint32_t)(t / 10u));
    *p++ = '.';
    *p++ = (char)('0' + (uint32_t)(t % 10u));
    return p;
}

static void append(const char* s, uint32_t n) {
    volatile struct zmb_log* l = &zmb_log;
    if (l->len + n + 1 > LOG_BYTES) return; /* full: the count says so (lines < tests) */
    for (uint32_t i = 0; i < n; i++) l->text[l->len + i] = s[i];
    l->text[l->len + n] = '\n';
    l->len += n + 1;
    l->lines++;
}

void log_begin(void) {
    volatile struct zmb_log* l = &zmb_log;
    l->done = 0, l->len = 0, l->lines = 0;
    l->magic = LOG_MAGIC;
}

static char* kv(char* p, const char* k, uint32_t v) {
    p = fmt_str(p, k);
    return fmt_u32(p, v);
}

void log_line(const bench_result* r) {
    char b[160], *p = fmt_str(b, "ZMBENCH name=");
    p = fmt_str(p, r->name);
    p = kv(p, " size=", r->size);
    p = kv(p, " cyc=", r->min);
    p = kv(p, " med=", r->med);
    p = kv(p, " ops=", r->ops);
    p = kv(p, " dwait=", r->dwait);
    p = kv(p, " dwr=", r->dwr);
    append(b, (uint32_t)(p - b));
}

void log_text(const char* s) {
    uint32_t n = 0;
    while (s[n]) n++;
    append(s, n);
}

void log_done(void) {
    log_text("ZMBENCH-END");
    zmb_log.done = 1;
}
