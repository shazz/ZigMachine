/* netdb.h for the SyncTERM cart (wasi-libc has none): name resolution, answered by the sockets
 * shim (kestrel_sock.c). The layout is POSIX's; the values are Linux musl's, so a later shim over
 * ZIGNIC's RESOLVE command can keep them. */
#ifndef KESTREL_NETDB_H
#define KESTREL_NETDB_H
#include <sys/socket.h>
#include <netinet/in.h>

struct addrinfo {
    int ai_flags, ai_family, ai_socktype, ai_protocol;
    socklen_t ai_addrlen;
    struct sockaddr *ai_addr;
    char *ai_canonname;
    struct addrinfo *ai_next;
};
struct hostent {
    char *h_name;
    char **h_aliases;
    int h_addrtype, h_length;
    char **h_addr_list;
};
#define h_addr h_addr_list[0]

#define AI_PASSIVE 0x01
#define AI_CANONNAME 0x02
#define AI_NUMERICHOST 0x04
#define AI_V4MAPPED 0x08
#define AI_ALL 0x10
#define AI_ADDRCONFIG 0x20
#define AI_NUMERICSERV 0x400
#define NI_NUMERICHOST 0x01
#define NI_NUMERICSERV 0x02
#define NI_NOFQDN 0x04
#define NI_NAMEREQD 0x08
#define NI_DGRAM 0x10
#define NI_MAXHOST 255
#define NI_MAXSERV 32
#define EAI_BADFLAGS -1
#define EAI_NONAME -2
#define EAI_AGAIN -3
#define EAI_FAIL -4
#define EAI_FAMILY -6
#define EAI_SOCKTYPE -7
#define EAI_SERVICE -8
#define EAI_MEMORY -10
#define EAI_SYSTEM -11
#define HOST_NOT_FOUND 1
#define TRY_AGAIN 2
#define NO_RECOVERY 3
#define NO_DATA 4

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
const char *gai_strerror(int code);
int getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv,
                socklen_t servlen, int flags);
struct hostent *gethostbyname(const char *name);
struct hostent *gethostbyaddr(const void *addr, socklen_t len, int type);
extern int h_errno;
#endif
