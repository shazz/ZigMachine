# _beginthread is kestrel_threads.c's: a fiber started on the thread's own void (*)(void *) function. Through
# pthread_create it would be called as void *(*)(void *), a signature mismatch that traps in wasm, and on
# a 256 KB stack each (upstream's minimum), more than the cart window has for four threads.
s/^ulong _beginthread(void (\*start_address)( void \* )$/static ulong upstream_beginthread(void (*start_address)( void * )/
