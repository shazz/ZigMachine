/* The libc cRSID links on wasm32-freestanding (machine-audio.wasm has no libc; compiler_rt gives
 * memset/memcpy). The string functions serve cRSID_getPlaylengths, which returns before any of
 * them while no SongLengths database is set (zm_sid.c never sets one): they exist so the module
 * links, and are correct anyway. The two formatters are never reached and do nothing. */
#include <stdarg.h>

#include "string.h"
#include "stdio.h"

size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

char *strchr(const char *s, int c) {
    for (;; s++) {
        if (*s == (char)c) return (char *)s;
        if (!*s) return NULL;
    }
}

int strncmp(const char *a, const char *b, size_t n) {
    for (; n; n--, a++, b++) {
        if (*a != *b || !*a) return (unsigned char)*a - (unsigned char)*b;
    }
    return 0;
}

static int in_set(char c, const char *set) {
    for (; *set; set++)
        if (*set == c) return 1;
    return 0;
}

size_t strcspn(const char *s, const char *reject) {
    size_t n = 0;
    while (s[n] && !in_set(s[n], reject)) n++;
    return n;
}

size_t strspn(const char *s, const char *accept) {
    size_t n = 0;
    while (s[n] && in_set(s[n], accept)) n++;
    return n;
}

char *strncpy(char *d, const char *s, size_t n) {
    size_t i = 0;
    for (; i < n && s[i]; i++) d[i] = s[i];
    for (; i < n; i++) d[i] = 0;
    return d;
}

int sprintf(char *s, const char *fmt, ...) {
    (void)fmt;
    s[0] = 0;
    return 0;
}

int sscanf(const char *s, const char *fmt, ...) {
    (void)s, (void)fmt;
    return 0;
}
