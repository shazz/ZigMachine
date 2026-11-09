/* The benchmark cart's libc-lite (apps/c/bench/kestrel/rt.c): output is captured into rt_out, not printed. */
#ifndef KS_STDIO_H
#define KS_STDIO_H
#include <stddef.h>
#include <stdarg.h>
int printf(const char *fmt, ...);
int fprintf(void *f, const char *fmt, ...);
int snprintf(char *buf, size_t cap, const char *fmt, ...);
int vsnprintf(char *buf, size_t cap, const char *fmt, va_list ap);
char *fgets(char *buf, int n, void *f);
#define stderr ((void *)0)
#define stdin ((void *)0)
#endif
