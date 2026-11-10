// The bench's log lines with no libc: append text, unsigned decimals and hex to one buffer.
#ifndef ASTRO_FMT_H
#define ASTRO_FMT_H

static char fm_buf[192];
static unsigned fm_len;

static void fm_reset(void) { fm_len = 0, fm_buf[0] = 0; }
static void fm_s(const char* s) {
    while (*s && fm_len + 1 < sizeof fm_buf) fm_buf[fm_len++] = *s++;
    fm_buf[fm_len] = 0;
}
static void fm_u(unsigned long long v) {
    char t[24];
    int n = 0;
    do t[n++] = (char)('0' + v % 10), v /= 10; while (v);
    while (n && fm_len + 1 < sizeof fm_buf) fm_buf[fm_len++] = t[--n];
    fm_buf[fm_len] = 0;
}
static void fm_x(unsigned long long v) {
    for (int i = 60; i >= 0 && fm_len + 1 < sizeof fm_buf; i -= 4) fm_buf[fm_len++] = "0123456789abcdef"[(v >> i) & 15];
    fm_buf[fm_len] = 0;
}
// "name=<ns per op>" from `us` microseconds over `n` ops; "name=-" with no clock
static void fm_ns(const char* name, unsigned us, unsigned n, int clocked) {
    fm_s(" "), fm_s(name), fm_s("=");
    if (!clocked) { fm_s("-"); return; }
    fm_u((unsigned long long)us * 1000u / n);
}
static unsigned fm_strlen(const char* s) { unsigned n = 0; while (s[n]) n++; return n; }

#endif
