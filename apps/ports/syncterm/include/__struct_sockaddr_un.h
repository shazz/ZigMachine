/* struct sockaddr_un with its path (wasi-libc leaves it out: WASI has no UNIX-domain sockets). The SyncTERM
 * cart has none either; xpdev names sun_path in code that never runs (multisock.c, sockwrap.c). */
#ifndef __wasilibc___struct_sockaddr_un_h
#define __wasilibc___struct_sockaddr_un_h
#include <__typedef_sa_family_t.h>
struct sockaddr_un {
    sa_family_t sun_family;
    char sun_path[108];
};
#endif
