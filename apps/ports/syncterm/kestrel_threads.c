/* xpdev's _beginthread (patches/threadwrap.c.sed) as a fiber (../kestrel_sdl2/src/opt/kestrel_fiber.c).
 * SyncTERM's threads: its main (kestrel_main.c), ciolib's mouse thread, the telnet input and output pumps,
 * and a few short-lived ones (the BBS-list download, the beeper) that this build never starts. */
#include "kestrel_fiber.h"

void kestrel_log(const char *m);

#define THREAD_STACK (64u * 1024u)   /* the pumps' deepest call is select -> the transport: a few KB */

unsigned long _beginthread(void (*fn)(void *), unsigned stack_size, void *arg)
{
    unsigned bytes = stack_size && stack_size < THREAD_STACK ? THREAD_STACK : (stack_size ? stack_size : THREAD_STACK);
    if (bytes > 256u * 1024u) bytes = 256u * 1024u;
    int id = kfib_spawn(fn, arg, bytes);
    if (!id) { kestrel_log("syncterm: _beginthread: no fiber"); return (unsigned long)-1; }
    return (unsigned long)id;
}
