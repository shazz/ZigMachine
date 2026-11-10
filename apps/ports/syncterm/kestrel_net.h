/* The BSD sockets SyncTERM calls, and the one interface they run on (struct knet_transport).
 *
 * This is the shape docs/GEM_NET.md's N6 shim takes: kestrel_sock.c implements every call below over
 * `knet`, a transport of at most KNET_SOCKETS stream sockets. Today the transport is the in-cart fake BBS
 * (kestrel_fakebbs.c); ZIGNIC's 8 hardware sockets (OPEN / CONNECT / SEND / RECV / CLOSE / RESOLVE and
 * their rings) replace it by providing another struct knet_transport, with nothing above it changing.
 *
 * The names are renamed (object-like macros, force-included before any system header) because wasi-libc
 * already defines recv / send / poll / select / shutdown / close / ioctl / fcntl over WASI file
 * descriptors; the renaming makes every user consistent, struct members included (conn_api.close). */
#ifndef KESTREL_NET_H
#define KESTREL_NET_H
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <poll.h>
#include <netdb.h>

#define KNET_SOCKETS 8               /* ZIGNIC's socket count */
#define KNET_FD_BASE 1000            /* a socket's file descriptor: KNET_FD_BASE + its number */

enum { KNET_FREE, KNET_CONNECTING, KNET_OPEN, KNET_CLOSED, KNET_REFUSED };

struct knet_transport {
    const char *name;                                          /* for the status line: "mock", "zignic" */
    int (*resolve)(const char *host, uint32_t *ip);            /* host name -> IPv4 (host order); 0 = found */
    int (*open)(int s, uint32_t ip, uint16_t port);            /* start a TCP connect on socket s; 0 = started */
    int (*state)(int s);                                       /* KNET_CONNECTING .. KNET_REFUSED */
    int (*rx_avail)(int s);                                    /* bytes ready to receive */
    int (*rx)(int s, void *buf, int len, int peek);            /* receive up to len bytes (peek: leave them) */
    int (*tx_room)(int s);                                     /* bytes send can take now */
    int (*tx)(int s, const void *buf, int len);                /* send; returns bytes taken */
    void (*disconnect)(int s);                                 /* close it (both directions) */
};
extern const struct knet_transport *knet;

struct sockaddr;
int knet_socket(int domain, int type, int proto);
int knet_connect(int fd, const struct sockaddr *a, socklen_t len);
int knet_setsockopt(int fd, int level, int opt, const void *v, socklen_t len);
int knet_getsockopt(int fd, int level, int opt, void *v, socklen_t *len);
int knet_getpeername(int fd, struct sockaddr *a, socklen_t *len);
int knet_getsockname(int fd, struct sockaddr *a, socklen_t *len);
ssize_t knet_recv(int fd, void *buf, size_t n, int flags);
ssize_t knet_send(int fd, const void *buf, size_t n, int flags);
int knet_shutdown(int fd, int how);
int knet_close(int fd);
int knet_poll(struct pollfd *f, nfds_t n, int timeout_ms);
int knet_select(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv);
int knet_ioctl(int fd, int req, ...);
int knet_fcntl(int fd, int cmd, ...);
int knet_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
void knet_freeaddrinfo(struct addrinfo *res);
const char *knet_gai_strerror(int code);
int knet_getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv,
                     socklen_t servlen, int flags);
struct hostent *knet_gethostbyname(const char *name);
struct hostent *knet_gethostbyaddr(const void *addr, socklen_t len, int type);

/* The shared layer (../kestrel_sdl2) is built with KESTREL_NET_NO_RENAME: kestrel_wasi.c defines the real close. */
#ifndef KESTREL_NET_NO_RENAME
#define socket knet_socket
#define connect knet_connect
#define setsockopt knet_setsockopt
#define getsockopt knet_getsockopt
#define getpeername knet_getpeername
#define getsockname knet_getsockname
#define recv knet_recv
#define send knet_send
#define shutdown knet_shutdown
#define close knet_close
#define poll knet_poll
#define select knet_select
#define ioctl knet_ioctl
#define fcntl knet_fcntl
#define getaddrinfo knet_getaddrinfo
#define freeaddrinfo knet_freeaddrinfo
#define gai_strerror knet_gai_strerror
#define getnameinfo knet_getnameinfo
#define gethostbyname knet_gethostbyname
#define gethostbyaddr knet_gethostbyaddr
#endif
#endif
