/* Cooperative threads for C ports whose program is threaded (SyncTERM: its main loop, the telnet
 * input and output pumps, the cursor blinker). Opt-in: src/opt/kestrel_fiber.c (the fibers, on
 * binaryen Asyncify) and src/opt/kestrel_pthread.c (pthread and sleeps over them). A port that
 * force-includes this header gets every pthread call it makes renamed to the fiber versions.
 *
 * One fiber runs at a time and only gives the CPU up at a blocking call (a contended lock, a
 * condition wait, a sleep, a select/poll on a socket), so a critical section between two such
 * calls is atomic, as on a single core with no preemption. The cart's frame() runs the fibers:
 * each one that can make progress is resumed until it blocks again (kfib_run). Time is the
 * frame clock (kfib_now_us), so a sleep ends at a frame, never inside one. */
#ifndef KESTREL_FIBER_H
#define KESTREL_FIBER_H
#include <stdint.h>
#include <pthread.h>
#include <time.h>

typedef void (*kfib_fn)(void *arg);
typedef int (*kfib_ready_fn)(void *arg);

/* A new fiber running fn(arg) on its own C stack; it first runs at the next kfib_run. Returns its
 * id (>= 1), 0 when the fiber table or the heap is full. */
int kfib_spawn(kfib_fn fn, void *arg, unsigned stack_bytes);
/* The running fiber's id, 0 outside any fiber (boot, frame, an export). */
int kfib_self(void);
/* Block the running fiber until ready(arg) != 0 or the frame clock reaches deadline_us (0: no
 * deadline). Returns 1 when ready, 0 on the deadline. Outside a fiber it cannot block: it
 * returns ready(arg) at once. */
int kfib_block(kfib_ready_fn ready, void *arg, uint64_t deadline_us);
/* Let the other fibers run: the caller carries on at the next frame. */
void kfib_yield(void);
/* Run every fiber that can make progress until each one blocks (at most `passes` rounds). */
void kfib_run(unsigned passes);
/* The frame clock, microseconds; kfib_tick(us) advances it (once a frame, from frame()). */
uint64_t kfib_now_us(void);
void kfib_tick(uint32_t us);
/* Fibers alive (not finished), and the deepest Asyncify save area used so far (bytes). */
int kfib_alive(void);
unsigned kfib_save_peak(void);

/* --- pthread / sleep, renamed onto kestrel_pthread.c --- */
#define pthread_create kfib_pthread_create
#define pthread_detach kfib_pthread_detach
#define pthread_join kfib_pthread_join
#define pthread_self kfib_pthread_self
#define pthread_mutex_init kfib_mutex_init
#define pthread_mutex_lock kfib_mutex_lock
#define pthread_mutex_trylock kfib_mutex_trylock
#define pthread_mutex_unlock kfib_mutex_unlock
#define pthread_mutex_destroy kfib_mutex_destroy
#define pthread_mutexattr_init kfib_mutexattr_init
#define pthread_mutexattr_settype kfib_mutexattr_settype
#define pthread_mutexattr_destroy kfib_mutexattr_destroy
#define pthread_cond_init kfib_cond_init
#define pthread_cond_wait kfib_cond_wait
#define pthread_cond_timedwait kfib_cond_timedwait
#define pthread_cond_signal kfib_cond_signal
#define pthread_cond_broadcast kfib_cond_broadcast
#define pthread_cond_destroy kfib_cond_destroy
#define pthread_rwlock_init kfib_rwlock_init
#define pthread_rwlock_rdlock kfib_rwlock_rdlock
#define pthread_rwlock_wrlock kfib_rwlock_wrlock
#define pthread_rwlock_tryrdlock kfib_rwlock_tryrdlock
#define pthread_rwlock_trywrlock kfib_rwlock_trywrlock
#define pthread_rwlock_unlock kfib_rwlock_unlock
#define pthread_rwlock_destroy kfib_rwlock_destroy
#define pthread_once kfib_once
#define pthread_attr_init kfib_attr_init
#define pthread_attr_destroy kfib_attr_destroy
#define pthread_attr_setstacksize kfib_attr_setstacksize
#define pthread_attr_getstacksize kfib_attr_getstacksize
#define pthread_attr_setdetachstate kfib_attr_setdetachstate
#define pthread_setname_np kfib_setname_np
#define pthread_set_name_np kfib_setname_np
#define sched_yield kfib_sched_yield
#define nanosleep kfib_nanosleep
#define usleep kfib_usleep
#define sleep kfib_sleep

int kfib_pthread_create(pthread_t *t, const pthread_attr_t *a, void *(*fn)(void *), void *arg);
int kfib_pthread_detach(pthread_t t);
int kfib_pthread_join(pthread_t t, void **ret);
pthread_t kfib_pthread_self(void);
int kfib_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *a);
int kfib_mutex_lock(pthread_mutex_t *m);
int kfib_mutex_trylock(pthread_mutex_t *m);
int kfib_mutex_unlock(pthread_mutex_t *m);
int kfib_mutex_destroy(pthread_mutex_t *m);
int kfib_mutexattr_init(pthread_mutexattr_t *a);
int kfib_mutexattr_settype(pthread_mutexattr_t *a, int type);
int kfib_mutexattr_destroy(pthread_mutexattr_t *a);
int kfib_cond_init(pthread_cond_t *c, const pthread_condattr_t *a);
int kfib_cond_wait(pthread_cond_t *c, pthread_mutex_t *m);
int kfib_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *abstime);
int kfib_cond_signal(pthread_cond_t *c);
int kfib_cond_broadcast(pthread_cond_t *c);
int kfib_cond_destroy(pthread_cond_t *c);
int kfib_rwlock_init(pthread_rwlock_t *l, const pthread_rwlockattr_t *a);
int kfib_rwlock_rdlock(pthread_rwlock_t *l);
int kfib_rwlock_wrlock(pthread_rwlock_t *l);
int kfib_rwlock_tryrdlock(pthread_rwlock_t *l);
int kfib_rwlock_trywrlock(pthread_rwlock_t *l);
int kfib_rwlock_unlock(pthread_rwlock_t *l);
int kfib_rwlock_destroy(pthread_rwlock_t *l);
int kfib_once(pthread_once_t *o, void (*init)(void));
int kfib_attr_init(pthread_attr_t *a);
int kfib_attr_destroy(pthread_attr_t *a);
int kfib_attr_setstacksize(pthread_attr_t *a, size_t s);
int kfib_attr_getstacksize(const pthread_attr_t *a, size_t *s);
int kfib_attr_setdetachstate(pthread_attr_t *a, int d);
int kfib_setname_np(pthread_t t, const char *name);
int kfib_sched_yield(void);
int kfib_nanosleep(const struct timespec *req, struct timespec *rem);
int kfib_usleep(unsigned us);
unsigned kfib_sleep(unsigned s);
#endif
