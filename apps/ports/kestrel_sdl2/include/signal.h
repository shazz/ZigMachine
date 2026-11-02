/* signal.h shim: the cart has no signals. pt2_main.c installs a crash handler; here it is a no-op. */
#ifndef KESTREL_SIGNAL_SHIM_H
#define KESTREL_SIGNAL_SHIM_H
#define SIGILL 4
#define SIGABRT 6
#define SIGFPE 8
#define SIGSEGV 11
#define SA_RESETHAND 0x80000000
struct sigaction { void (*sa_handler)(int); int sa_flags; };
static inline int sigaction(int s, const struct sigaction *a, struct sigaction *o) { (void)s; (void)a; (void)o; return 0; }
#endif
