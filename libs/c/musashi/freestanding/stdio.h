// Freestanding stand-in for <stdio.h>. Musashi reaches for stdio only through
// its logging (M68K_LOG_ENABLE, off) and the disassembler (not compiled here),
// so these are declarations that nothing ends up calling — declared rather than
// defined, so a real call would fail loudly at link time instead of silently
// doing nothing.
#ifndef ZM_FREESTANDING_STDIO_H
#define ZM_FREESTANDING_STDIO_H

typedef struct _ZM_FILE FILE;

extern FILE *stderr;

extern int printf(const char *fmt, ...);
extern int sscanf(const char *s, const char *fmt, ...);
extern int sprintf(char *buf, const char *fmt, ...);
extern int fprintf(FILE *f, const char *fmt, ...);
extern int vfprintf(FILE *f, const char *fmt, __builtin_va_list ap);
extern int fflush(FILE *f);

#endif
