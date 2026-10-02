/* wasm-rt.h includes <pthread.h> whenever C11 is available, for the mutex that
 * guards shared-memory growth. The rv32 host is one thread and never grows a
 * shared memory, so the mutex is a no-op that always succeeds. */
#ifndef ZM_SHIM_PTHREAD_H
#define ZM_SHIM_PTHREAD_H

typedef int pthread_mutex_t;
typedef int pthread_mutexattr_t;

static inline int pthread_mutex_init(pthread_mutex_t* m, const pthread_mutexattr_t* a) { (void)a; *m = 0; return 0; }
static inline int pthread_mutex_lock(pthread_mutex_t* m) { (void)m; return 0; }
static inline int pthread_mutex_unlock(pthread_mutex_t* m) { (void)m; return 0; }
static inline int pthread_mutex_destroy(pthread_mutex_t* m) { (void)m; return 0; }

#endif
