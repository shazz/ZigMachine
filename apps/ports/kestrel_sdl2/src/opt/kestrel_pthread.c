/* pthread, sched_yield and the sleeps over the fibers (kestrel_fiber.c; the model is in
 * include/kestrel_fiber.h). wasi-libc's single-threaded pthread stubs would let a condition wait
 * return at once, and a program that waits for another thread would spin forever: here a wait
 * blocks the fiber until the condition can hold. The pthread objects keep wasi-libc's sizes;
 * ours live inside them. */
#include <errno.h>
#include <string.h>
#include "kestrel_fiber.h"

typedef struct { int owner, count, recursive; } kmutex;            /* owner: fiber id + 1, 0 = free */
typedef struct { unsigned gen; } kcond;
typedef struct { int readers, writer; } krw;                      /* writer: fiber id + 1 */
typedef struct { int type; } kmattr;
_Static_assert(sizeof(kmutex) <= sizeof(pthread_mutex_t), "mutex fits");
_Static_assert(sizeof(kcond) <= sizeof(pthread_cond_t), "cond fits");
_Static_assert(sizeof(krw) <= sizeof(pthread_rwlock_t), "rwlock fits");
_Static_assert(sizeof(kmattr) <= sizeof(pthread_mutexattr_t), "mutexattr fits");
#define KM(m) ((kmutex *)(void *)(m))
#define KC(c) ((kcond *)(void *)(c))
#define KR(l) ((krw *)(void *)(l))
static int me(void) { return kfib_self() + 1; }   /* outside a fiber: 1 */

/* --- threads --- */
typedef struct { void *(*fn)(void *); void *arg; } start_t;
static start_t starts[32];
static void tramp(void *p) { start_t *s = p; void *(*fn)(void *) = s->fn; void *a = s->arg; s->fn = 0; fn(a); }

int kfib_pthread_create(pthread_t *t, const pthread_attr_t *a, void *(*fn)(void *), void *arg)
{
    size_t stack = 64 * 1024;
    if (a) kfib_attr_getstacksize(a, &stack);
    int slot = 0;
    while (slot < 32 && starts[slot].fn) slot++;
    if (slot == 32) return EAGAIN;
    starts[slot].fn = fn;
    starts[slot].arg = arg;
    int id = kfib_spawn(tramp, &starts[slot], (unsigned)stack);
    if (!id) { starts[slot].fn = 0; return EAGAIN; }
    if (t) *t = (pthread_t)(uintptr_t)id;
    return 0;
}
int kfib_pthread_detach(pthread_t t) { (void)t; return 0; }
int kfib_pthread_join(pthread_t t, void **ret) { (void)t; if (ret) *ret = 0; return ENOSYS; }
pthread_t kfib_pthread_self(void) { return (pthread_t)(uintptr_t)me(); }
int kfib_setname_np(pthread_t t, const char *name) { (void)t; (void)name; return 0; }

int kfib_attr_init(pthread_attr_t *a) { memset(a, 0, sizeof *a); return 0; }
int kfib_attr_destroy(pthread_attr_t *a) { (void)a; return 0; }
int kfib_attr_setstacksize(pthread_attr_t *a, size_t s) { memcpy(a, &s, sizeof s); return 0; }
int kfib_attr_getstacksize(const pthread_attr_t *a, size_t *s)
{
    size_t v;
    memcpy(&v, a, sizeof v);
    *s = v ? v : 64 * 1024;
    return 0;
}
int kfib_attr_setdetachstate(pthread_attr_t *a, int d) { (void)a; (void)d; return 0; }

/* --- mutexes --- */
int kfib_mutexattr_init(pthread_mutexattr_t *a) { memset(a, 0, sizeof *a); return 0; }
int kfib_mutexattr_settype(pthread_mutexattr_t *a, int type) { ((kmattr *)(void *)a)->type = type; return 0; }
int kfib_mutexattr_destroy(pthread_mutexattr_t *a) { (void)a; return 0; }
int kfib_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *a)
{
    memset(m, 0, sizeof *m);
    KM(m)->recursive = a && ((const kmattr *)(const void *)a)->type == PTHREAD_MUTEX_RECURSIVE;
    return 0;
}
int kfib_mutex_destroy(pthread_mutex_t *m) { (void)m; return 0; }
static int mutex_free(void *m) { return KM(m)->owner == 0; }
int kfib_mutex_trylock(pthread_mutex_t *m)
{
    kmutex *k = KM(m);
    if (k->owner == me() && k->recursive) { k->count++; return 0; }
    if (k->owner) return EBUSY;
    k->owner = me();
    k->count = 1;
    return 0;
}
int kfib_mutex_lock(pthread_mutex_t *m)
{
    kmutex *k = KM(m);
    if (k->owner == me() && !k->recursive) return EDEADLK;
    while (kfib_mutex_trylock(m) == EBUSY)
        if (!kfib_block(mutex_free, m, 0) && !kfib_self()) return EBUSY;   /* outside a fiber: cannot wait */
    return 0;
}
int kfib_mutex_unlock(pthread_mutex_t *m)
{
    kmutex *k = KM(m);
    if (k->owner != me()) return EPERM;
    if (--k->count == 0) k->owner = 0;
    return 0;
}

/* --- condition variables: a generation count; a wait ends when it moves (or at the deadline) --- */
typedef struct { kcond *c; unsigned gen; } cwait;
static int cond_moved(void *p) { cwait *w = p; return w->c->gen != w->gen; }
static uint64_t abs_us(const struct timespec *t) { return (uint64_t)t->tv_sec * 1000000u + (uint64_t)t->tv_nsec / 1000u; }

int kfib_cond_init(pthread_cond_t *c, const pthread_condattr_t *a) { (void)a; memset(c, 0, sizeof *c); return 0; }
int kfib_cond_destroy(pthread_cond_t *c) { (void)c; return 0; }
int kfib_cond_signal(pthread_cond_t *c) { KC(c)->gen++; return 0; }      /* wakes all: waiters re-check */
int kfib_cond_broadcast(pthread_cond_t *c) { KC(c)->gen++; return 0; }
static int cond_wait_until(pthread_cond_t *c, pthread_mutex_t *m, uint64_t deadline)
{
    cwait w = { KC(c), KC(c)->gen };
    kmutex *k = KM(m);
    int depth = k->count;
    k->owner = 0;
    k->count = 0;
    int moved = kfib_block(cond_moved, &w, deadline ? deadline : 0);
    if (!kfib_self() && !moved && !deadline) moved = 1;   /* outside a fiber: a wait cannot block */
    kfib_mutex_lock(m);
    k->count = depth;
    return moved ? 0 : ETIMEDOUT;
}
int kfib_cond_wait(pthread_cond_t *c, pthread_mutex_t *m) { return cond_wait_until(c, m, 0); }
/* abstime is CLOCK_REALTIME / CLOCK_MONOTONIC: both are the frame clock on the cart (kestrel_wasi.c). */
int kfib_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *t)
{
    uint64_t d = abs_us(t);
    return cond_wait_until(c, m, d ? d : 1);
}

/* --- read/write locks --- */
static int rw_no_writer(void *p) { return KR(p)->writer == 0; }
static int rw_idle(void *p) { return KR(p)->writer == 0 && KR(p)->readers == 0; }
int kfib_rwlock_init(pthread_rwlock_t *l, const pthread_rwlockattr_t *a) { (void)a; memset(l, 0, sizeof *l); return 0; }
int kfib_rwlock_destroy(pthread_rwlock_t *l) { (void)l; return 0; }
int kfib_rwlock_tryrdlock(pthread_rwlock_t *l)
{
    if (KR(l)->writer && KR(l)->writer != me()) return EBUSY;
    KR(l)->readers++;
    return 0;
}
int kfib_rwlock_trywrlock(pthread_rwlock_t *l)
{
    if (!rw_idle(l)) return EBUSY;
    KR(l)->writer = me();
    return 0;
}
int kfib_rwlock_rdlock(pthread_rwlock_t *l)
{
    while (kfib_rwlock_tryrdlock(l) == EBUSY)
        if (!kfib_block(rw_no_writer, l, 0) && !kfib_self()) return EBUSY;
    return 0;
}
int kfib_rwlock_wrlock(pthread_rwlock_t *l)
{
    while (kfib_rwlock_trywrlock(l) == EBUSY)
        if (!kfib_block(rw_idle, l, 0) && !kfib_self()) return EBUSY;
    return 0;
}
int kfib_rwlock_unlock(pthread_rwlock_t *l)
{
    if (KR(l)->writer == me()) KR(l)->writer = 0;
    else if (KR(l)->readers > 0) KR(l)->readers--;
    return 0;
}

int kfib_once(pthread_once_t *o, void (*init)(void))
{
    if (*(volatile int *)o) return 0;
    *(volatile int *)o = 1;
    init();
    return 0;
}

/* --- yields and sleeps: a sleep ends at the first frame at or after its deadline --- */
int kfib_sched_yield(void) { kfib_yield(); return 0; }
static void sleep_us(uint64_t us)
{
    if (!kfib_self()) return;
    if (us == 0) { kfib_yield(); return; }
    kfib_block(0, 0, kfib_now_us() + us);
}
int kfib_nanosleep(const struct timespec *req, struct timespec *rem)
{
    sleep_us((uint64_t)req->tv_sec * 1000000u + (uint64_t)req->tv_nsec / 1000u);
    if (rem) { rem->tv_sec = 0; rem->tv_nsec = 0; }
    return 0;
}
int kfib_usleep(unsigned us) { sleep_us(us); return 0; }
unsigned kfib_sleep(unsigned s) { sleep_us((uint64_t)s * 1000000u); return 0; }
