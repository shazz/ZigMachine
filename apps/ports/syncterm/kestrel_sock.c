/* BSD stream sockets over a knet transport (kestrel_net.h): the calls SyncTERM's conn.c, rlogin.c and
 * xpdev's sockwrap.c make. A socket is a file descriptor KNET_FD_BASE + n; every other descriptor (the
 * floppy's files) goes to wasi-libc's own close / ioctl / fcntl. A call that would block (a blocking connect,
 * recv with nothing waiting, send with no room, poll / select with a timeout) blocks its fiber
 * (kestrel_fiber.h) until the transport can answer or the timeout passes; non-blocking sockets (FIONBIO,
 * O_NONBLOCK) answer EAGAIN / EINPROGRESS at once, as on Linux. */
#include <errno.h>
#include <string.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <stdarg.h>
#include "kestrel_net.h"
#include "kestrel_fiber.h"

static struct { int used, nonblock, shut; uint32_t ip; uint16_t port; } sk[KNET_SOCKETS];

static int sock_of(int fd)
{
    int s = fd - KNET_FD_BASE;
    return s >= 0 && s < KNET_SOCKETS && sk[s].used ? s : -1;
}
static int fail(int e) { errno = e; return -1; }
static uint64_t until(int ms) { return ms < 0 ? 0 : kfib_now_us() + (uint64_t)(ms ? ms : 1) * 1000u; }

int knet_socket(int domain, int type, int proto)
{
    (void)proto;
    if (domain != AF_INET) return fail(EAFNOSUPPORT);
    if ((type & 0xf) != SOCK_STREAM) return fail(EPROTONOSUPPORT);
    for (int s = 0; s < KNET_SOCKETS; s++)
        if (!sk[s].used) {
            memset(&sk[s], 0, sizeof sk[s]);
            sk[s].used = 1;
            sk[s].nonblock = (type & SOCK_NONBLOCK) != 0;
            return KNET_FD_BASE + s;
        }
    return fail(EMFILE);
}

static int not_connecting(void *p) { return knet->state((int)(intptr_t)p) != KNET_CONNECTING; }
int knet_connect(int fd, const struct sockaddr *a, socklen_t len)
{
    int s = sock_of(fd);
    if (s < 0) return fail(ENOTSOCK);
    if (!a || len < sizeof(struct sockaddr_in) || a->sa_family != AF_INET) return fail(EAFNOSUPPORT);
    const struct sockaddr_in *in = (const struct sockaddr_in *)a;
    sk[s].ip = ntohl(in->sin_addr.s_addr);
    sk[s].port = ntohs(in->sin_port);
    if (knet->open(s, sk[s].ip, sk[s].port) != 0) return fail(ECONNREFUSED);
    if (knet->state(s) == KNET_CONNECTING) {
        if (sk[s].nonblock) return fail(EINPROGRESS);
        kfib_block(not_connecting, (void *)(intptr_t)s, 0);
    }
    return knet->state(s) == KNET_OPEN ? 0 : fail(ECONNREFUSED);
}

int knet_setsockopt(int fd, int level, int opt, const void *v, socklen_t len)
{
    (void)level; (void)opt; (void)v; (void)len;   /* keepalive, nodelay, linger, buffers: nothing to tune */
    return sock_of(fd) < 0 ? fail(ENOTSOCK) : 0;
}
int knet_getsockopt(int fd, int level, int opt, void *v, socklen_t *len)
{
    int s = sock_of(fd);
    if (s < 0) return fail(ENOTSOCK);
    int val = 0;
    if (level == SOL_SOCKET && opt == SO_ERROR) val = knet->state(s) == KNET_REFUSED ? ECONNREFUSED : 0;
    if (v && len && *len >= sizeof val) { memcpy(v, &val, sizeof val); *len = sizeof val; }
    return 0;
}

static int sockname(int fd, struct sockaddr *a, socklen_t *len, int peer)
{
    int s = sock_of(fd);
    if (s < 0) return fail(ENOTSOCK);
    struct sockaddr_in in = { .sin_family = AF_INET };
    in.sin_addr.s_addr = htonl(peer ? sk[s].ip : 0x0a000001u);   /* the cart's own address: 10.0.0.1 */
    in.sin_port = htons(peer ? sk[s].port : 49152);
    if (a && len) { memcpy(a, &in, *len < sizeof in ? *len : sizeof in); *len = sizeof in; }
    return 0;
}
int knet_getpeername(int fd, struct sockaddr *a, socklen_t *len) { return sockname(fd, a, len, 1); }
int knet_getsockname(int fd, struct sockaddr *a, socklen_t *len) { return sockname(fd, a, len, 0); }

static int readable(void *p) { int s = (int)(intptr_t)p; return knet->rx_avail(s) > 0 || knet->state(s) != KNET_OPEN; }
static int writable(void *p) { int s = (int)(intptr_t)p; return knet->tx_room(s) > 0 || knet->state(s) != KNET_OPEN; }

ssize_t knet_recv(int fd, void *buf, size_t n, int flags)
{
    int s = sock_of(fd);
    if (s < 0) return fail(ENOTSOCK);
    if (!readable((void *)(intptr_t)s)) {
        if (sk[s].nonblock || (flags & MSG_DONTWAIT)) return fail(EAGAIN);
        kfib_block(readable, (void *)(intptr_t)s, 0);
    }
    if (knet->rx_avail(s) == 0) return knet->state(s) == KNET_REFUSED ? fail(ECONNREFUSED) : 0;   /* EOF */
    return knet->rx(s, buf, n > 0x7fffffff ? 0x7fffffff : (int)n, (flags & MSG_PEEK) != 0);
}

ssize_t knet_send(int fd, const void *buf, size_t n, int flags)
{
    int s = sock_of(fd);
    if (s < 0) return fail(ENOTSOCK);
    if (sk[s].shut || knet->state(s) != KNET_OPEN) return fail(EPIPE);
    if (!writable((void *)(intptr_t)s)) {
        if (sk[s].nonblock || (flags & MSG_DONTWAIT)) return fail(EAGAIN);
        kfib_block(writable, (void *)(intptr_t)s, 0);
        if (knet->state(s) != KNET_OPEN) return fail(EPIPE);
    }
    int room = knet->tx_room(s);
    return knet->tx(s, buf, (int)(n < (size_t)room ? n : (size_t)room));
}

int knet_shutdown(int fd, int how)
{
    int s = sock_of(fd);
    if (s < 0) return fail(ENOTSOCK);
    (void)how;
    if (!sk[s].shut) { sk[s].shut = 1; knet->disconnect(s); }
    return 0;
}

#undef close
int close(int fd);
int knet_close(int fd)
{
    int s = sock_of(fd);
    if (s < 0) return close(fd);
    if (!sk[s].shut) knet->disconnect(s);
    sk[s].used = 0;
    return 0;
}

/* --- poll / select: a socket's readiness; any other descriptor (a file) is always ready --- */
static short revents_of(int fd, short ev)
{
    int s = sock_of(fd);
    if (fd < 0) return 0;
    if (s < 0) return (short)(ev & (POLLIN | POLLOUT));
    int st = knet->state(s);
    short r = 0;
    if (st == KNET_CONNECTING) return 0;
    if (knet->rx_avail(s) > 0 || st != KNET_OPEN) r |= POLLIN;
    if (st == KNET_OPEN && knet->tx_room(s) > 0) r |= POLLOUT;
    if (st == KNET_CLOSED) r |= POLLHUP;
    if (st == KNET_REFUSED) r |= POLLERR;
    return (short)(r & (ev | POLLHUP | POLLERR));
}
typedef struct { struct pollfd *f; nfds_t n; } pollset;
static int poll_ready(void *p)
{
    pollset *ps = p;
    for (nfds_t i = 0; i < ps->n; i++) if (revents_of(ps->f[i].fd, ps->f[i].events)) return 1;
    return 0;
}
int knet_poll(struct pollfd *f, nfds_t n, int timeout_ms)
{
    pollset ps = { f, n };
    if (timeout_ms != 0 && !poll_ready(&ps)) kfib_block(poll_ready, &ps, until(timeout_ms));
    int count = 0;
    for (nfds_t i = 0; i < n; i++) { f[i].revents = revents_of(f[i].fd, f[i].events); count += f[i].revents != 0; }
    return count;
}

typedef struct { int n; fd_set *r, *w; fd_set ro, wo; } selset;
static int select_scan(selset *s)
{
    int count = 0;
    FD_ZERO(&s->ro); FD_ZERO(&s->wo);
    for (int fd = 0; fd < s->n; fd++) {
        if (s->r && FD_ISSET(fd, s->r) && revents_of(fd, POLLIN)) { FD_SET(fd, &s->ro); count++; }
        if (s->w && FD_ISSET(fd, s->w) && revents_of(fd, POLLOUT)) { FD_SET(fd, &s->wo); count++; }
    }
    return count;
}
static int select_ready(void *p) { return select_scan(p) > 0; }
int knet_select(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv)
{
    selset s = { n, r, w };
    int ms = tv ? (int)(tv->tv_sec * 1000 + tv->tv_usec / 1000) : -1;
    if (ms != 0 && !select_ready(&s)) kfib_block(select_ready, &s, until(ms));
    int count = select_scan(&s);
    if (r) *r = s.ro;
    if (w) *w = s.wo;
    if (e) FD_ZERO(e);
    return count;
}

/* --- FIONBIO / FIONREAD, O_NONBLOCK --- */
#undef ioctl
#undef fcntl
int ioctl(int fd, int req, ...);
int fcntl(int fd, int cmd, ...);
int knet_ioctl(int fd, int req, ...)
{
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    int s = sock_of(fd);
    if (s < 0) return ioctl(fd, req, arg);
    if (req == FIONBIO) { sk[s].nonblock = *(int *)arg != 0; return 0; }
    if (req == FIONREAD) { *(int *)arg = knet->rx_avail(s); return 0; }
    return fail(EINVAL);
}
int knet_fcntl(int fd, int cmd, ...)
{
    va_list ap;
    va_start(ap, cmd);
    long arg = va_arg(ap, long);
    va_end(ap);
    int s = sock_of(fd);
    if (s < 0) return fcntl(fd, cmd, arg);
    if (cmd == F_GETFL) return O_RDWR | (sk[s].nonblock ? O_NONBLOCK : 0);
    if (cmd == F_SETFL) { sk[s].nonblock = (arg & O_NONBLOCK) != 0; return 0; }
    return 0;
}
