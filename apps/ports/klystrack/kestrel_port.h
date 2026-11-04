/* Force-included into every klystrack / klystron source (-include): the KESTREL port's limits and hooks. */
#ifndef KESTREL_KLYSTRACK_PORT_H
#define KESTREL_KLYSTRACK_PORT_H
/* Upstream keeps 4096 patterns of 64 steps (2 MiB) and 32 x 2048 sequence entries (384 KiB) resident: more
 * than the 2 MiB cart window. patches/mused.h.sed and music.c.sed cap them; a song over the caps is refused
 * at load (the example songs on the floppy fit). */
#define KESTREL_MAX_PATTERNS 256
#define KESTREL_MAX_SEQUENCES 256
void kestrel_log(const char *m);
/* kestrel_sdl2/src/opt/kestrel_defer_group.c: a bevel or a string drawn as one group, copied from last frame's
 * draws when its key (and the renderer's state) did not change (patches/bevel.c.sed, font.c.sed). */
int kestrel_group_begin(void *renderer, void *texture, const unsigned *key, unsigned n, unsigned *out, unsigned nout);
void kestrel_group_end(const unsigned *out, unsigned nout);
void kestrel_window_nop(void *renderer);   /* a space keeps its place (font.c.sed) */
#include <sys/types.h>
int kestrel_vsnprintf(char *b, size_t n, const char *fmt, __builtin_va_list va);   /* kestrel_printf.c */
/* toolutil.c expands "~/" through the password database; the cart has none (no config path uses "~" here). */
#include <sys/types.h>
static inline uid_t getuid(void) { return 0; }
#endif
