/* Force-included into every klystrack / klystron source (-include): the KESTREL port's limits and hooks. */
#ifndef KESTREL_KLYSTRACK_PORT_H
#define KESTREL_KLYSTRACK_PORT_H
/* Upstream keeps 4096 patterns of 64 steps (2 MiB) and 32 x 2048 sequence entries (384 KiB) resident: more
 * than the 2 MiB cart window. patches/mused.h.sed and music.c.sed cap them; a song over the caps is refused
 * at load (the example songs on the floppy fit). */
#define KESTREL_MAX_PATTERNS 256
#define KESTREL_MAX_SEQUENCES 256
void kestrel_log(const char *m);
/* toolutil.c expands "~/" through the password database; the cart has none (no config path uses "~" here). */
#include <sys/types.h>
static inline uid_t getuid(void) { return 0; }
#endif
