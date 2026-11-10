/* Force-included into every SyncTERM / ciolib / xpdev source (-include): what wasi-libc lacks, and
 * the cooperative threads (kestrel_fiber.h) under SyncTERM's pthread calls. */
#ifndef KESTREL_SYNCTERM_PORT_H
#define KESTREL_SYNCTERM_PORT_H
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>

/* No users, no permissions: syncterm.c's umask(077) before writing its list. */
static inline mode_t umask(mode_t m) { (void)m; return 022; }
/* filewrap.c's lock(): advisory locks on a read-only floppy always "succeed". */
#ifndef F_RDLCK
#define F_RDLCK 0
#define F_WRLCK 1
#define F_UNLCK 2
#endif
/* xpdatetime.c: the cart's clock is UTC. */
#define timezone kestrel_timezone
#define daylight kestrel_daylight
static const long kestrel_timezone = 0;
static const int kestrel_daylight = 0;
/* sys/socket.h (wasip2's declarations) misses these option names; the shim ignores their values. */
#ifndef SO_LINGER
#define SO_DEBUG 1
#define SO_DONTROUTE 5
#define SO_BROADCAST 6
#define SO_OOBINLINE 10
#define SO_LINGER 13
#define SO_RCVLOWAT 18
#define SO_SNDLOWAT 19
#endif
#include "kestrel_fiber.h"
#include "kestrel_net.h"
#endif
