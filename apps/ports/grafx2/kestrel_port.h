/* Force-included into every GrafX2 source (-include): what wasi-libc lacks. */
#ifndef KESTREL_GRAFX2_PORT_H
#define KESTREL_GRAFX2_PORT_H
/* io.c's lock file: the floppy is read-only, so open(O_CREAT) already fails before lockf is reached. */
#ifndef F_TLOCK
#define F_TLOCK 2
#endif
static inline int lockf(int fd, int cmd, long len) { (void)fd; (void)cmd; (void)len; return 0; }
#endif
