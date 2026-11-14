/* signal.h for the SyncTERM cart: the cart has no signals and no processes. xpdev's genwrap.c
 * (check_pid/terminate_pid) and os_info.c only name them; nothing here is ever delivered. */
#ifndef KESTREL_SYNCTERM_SIGNAL_H
#define KESTREL_SYNCTERM_SIGNAL_H
#include <sys/types.h>
#define SIGHUP 1
#define SIGINT 2
#define SIGKILL 9
#define SIGPIPE 13
#define SIGTERM 15
#define SIGCHLD 17
#define SIGCONT 18
#define SIGSTOP 19
#define SIGTSTP 20
typedef void (*sighandler_t)(int);
#define SIG_DFL ((sighandler_t)0)
#define SIG_IGN ((sighandler_t)1)
#define SIG_ERR ((sighandler_t)-1)
static inline sighandler_t signal(int s, sighandler_t h) { (void)s; (void)h; return SIG_DFL; }
static inline int kill(pid_t p, int s) { (void)p; (void)s; return -1; }
#endif
