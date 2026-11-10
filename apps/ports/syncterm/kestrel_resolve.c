/* Name resolution for the sockets shim: getaddrinfo and friends over knet->resolve (kestrel_net.h). IPv4
 * only, as ZIGNIC's RESOLVE command answers. A dotted quad is parsed here and never asked of the transport. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netdb.h>
#include <netinet/in.h>
#include "kestrel_net.h"

int h_errno;

static int dotted(const char *s, uint32_t *ip)
{
    unsigned a, b, c, d;
    char tail;
    if (sscanf(s, "%u.%u.%u.%u%c", &a, &b, &c, &d, &tail) != 4 || a > 255 || b > 255 || c > 255 || d > 255) return 0;
    *ip = a << 24 | b << 16 | c << 8 | d;
    return 1;
}
static int lookup(const char *host, uint32_t *ip)
{
    if (!host) { *ip = 0x7f000001u; return 0; }
    if (dotted(host, ip)) return 0;
    return knet->resolve(host, ip);
}

int knet_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res)
{
    uint32_t ip;
    *res = 0;
    if (hints && hints->ai_family != AF_UNSPEC && hints->ai_family != AF_INET) return EAI_FAMILY;
    if (hints && hints->ai_socktype && hints->ai_socktype != SOCK_STREAM) return EAI_SOCKTYPE;
    if (lookup(node, &ip) != 0) return EAI_NONAME;
    long port = service ? strtol(service, 0, 10) : 0;
    if (port < 0 || port > 65535) return EAI_SERVICE;
    struct { struct addrinfo ai; struct sockaddr_in in; } *r = calloc(1, sizeof *r);
    if (!r) return EAI_MEMORY;
    r->in.sin_family = AF_INET;
    r->in.sin_port = htons((uint16_t)port);
    r->in.sin_addr.s_addr = htonl(ip);
    r->ai.ai_family = AF_INET;
    r->ai.ai_socktype = SOCK_STREAM;
    r->ai.ai_protocol = IPPROTO_TCP;
    r->ai.ai_addrlen = sizeof r->in;
    r->ai.ai_addr = (struct sockaddr *)&r->in;
    *res = &r->ai;
    return 0;
}
void knet_freeaddrinfo(struct addrinfo *res)
{
    while (res) { struct addrinfo *n = res->ai_next; free(res); res = n; }
}
const char *knet_gai_strerror(int code)
{
    switch (code) {
    case 0: return "Success";
    case EAI_NONAME: return "Name does not resolve";
    case EAI_FAMILY: return "Address family not supported";
    case EAI_SOCKTYPE: return "Socket type not supported";
    case EAI_SERVICE: return "Unknown service";
    case EAI_MEMORY: return "Out of memory";
    default: return "Name resolution failed";
    }
}

int knet_getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv,
                     socklen_t servlen, int flags)
{
    (void)flags;
    if (!sa || sa->sa_family != AF_INET || salen < sizeof(struct sockaddr_in)) return EAI_FAMILY;
    const struct sockaddr_in *in = (const struct sockaddr_in *)sa;
    uint32_t ip = ntohl(in->sin_addr.s_addr);
    if (host && hostlen) snprintf(host, hostlen, "%u.%u.%u.%u", ip >> 24, ip >> 16 & 255, ip >> 8 & 255, ip & 255);
    if (serv && servlen) snprintf(serv, servlen, "%u", ntohs(in->sin_port));
    return 0;
}

static struct hostent he;
static uint32_t he_addr;
static char *he_list[2] = { (char *)&he_addr, 0 }, *he_alias[1] = { 0 };
static char he_name[256];
struct hostent *knet_gethostbyname(const char *name)
{
    uint32_t ip;
    if (lookup(name, &ip) != 0) { h_errno = HOST_NOT_FOUND; return 0; }
    he_addr = htonl(ip);
    snprintf(he_name, sizeof he_name, "%s", name ? name : "localhost");
    he = (struct hostent){ he_name, he_alias, AF_INET, 4, he_list };
    return &he;
}
struct hostent *knet_gethostbyaddr(const void *addr, socklen_t len, int type)
{
    (void)addr; (void)len; (void)type;
    h_errno = HOST_NOT_FOUND;
    return 0;
}
