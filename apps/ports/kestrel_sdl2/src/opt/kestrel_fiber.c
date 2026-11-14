/* Fibers on binaryen Asyncify (the cart is post-processed with wasm-opt --asyncify, as GrafX2 is):
 * GrafX2's one coroutine (grafx2/kestrel_main.c) generalised to several, each with its own C
 * stack and its own Asyncify save area. See include/kestrel_fiber.h for the model.
 *
 * Switching: a fiber gives up the CPU in fib_suspend(), which starts an unwind; every frame up to
 * fib_main() saves its locals into the fiber's save area and returns, back to step() (which calls
 * stop_unwind, so binaryen leaves step() and its callers uninstrumented). Resuming calls fib_main()
 * again under a rewind, which re-enters every saved frame down to fib_suspend(), which stops the
 * rewind and returns into the program. The C stack (the linear-memory one, __stack_pointer) is not
 * part of what Asyncify saves, so each fiber has its own and step() switches __stack_pointer to it:
 * the frames a suspended fiber left there stay untouched while the others run. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "kestrel_fiber.h"

__attribute__((import_module("asyncify"), import_name("start_unwind"))) extern void asyncify_start_unwind(void *data);
__attribute__((import_module("asyncify"), import_name("stop_unwind"))) extern void asyncify_stop_unwind(void);
__attribute__((import_module("asyncify"), import_name("start_rewind"))) extern void asyncify_start_rewind(void *data);
__attribute__((import_module("asyncify"), import_name("stop_rewind"))) extern void asyncify_stop_rewind(void);
void kestrel_log(const char *m);

#define MAX_FIBERS 16
#define SAVE_BYTES (48u * 1024u)   /* Asyncify's save area per fiber: the locals of every suspended frame */
enum { FREE, NEW, BLOCKED, YIELDED, DONE };

typedef struct {
    void *top, *end;               /* Asyncify's header: where the next saved byte goes, and the limit */
    uint8_t save[SAVE_BYTES];
} save_area;

typedef struct {
    int state;
    kfib_fn fn;
    void *arg;
    uint8_t *stack;                /* malloc'd; the C stack grows down from stack + stack_bytes */
    unsigned stack_bytes;
    void *sp;                      /* __stack_pointer when it suspended */
    save_area *ad;
    kfib_ready_fn ready;
    void *rarg;
    uint64_t deadline;
    uint64_t ran_at;               /* the frame clock when it last yielded */
    int woke_ready;                /* kfib_block's answer */
} fiber;

static fiber fibs[MAX_FIBERS];
static int cur;                    /* running fiber's index + 1, 0 = none */
static int unwinding, rewinding;
static uint64_t now_us;
static unsigned save_peak;

static inline void *sp_get(void)
{
    void *p;
    __asm__ volatile(".globaltype __stack_pointer, i32\n\tglobal.get __stack_pointer\n\tlocal.set %0" : "=r"(p) :: "memory");
    return p;
}
static inline void sp_set(void *p)
{
    __asm__ volatile(".globaltype __stack_pointer, i32\n\tlocal.get %0\n\tglobal.set __stack_pointer" :: "r"(p) : "memory");
}

uint64_t kfib_now_us(void) { return now_us; }
void kfib_tick(uint32_t us) { now_us += us; }
int kfib_self(void) { return cur; }
unsigned kfib_save_peak(void) { return save_peak; }

int kfib_alive(void)
{
    int n = 0;
    for (int i = 0; i < MAX_FIBERS; i++) n += fibs[i].state != FREE && fibs[i].state != DONE;
    return n;
}

int kfib_spawn(kfib_fn fn, void *arg, unsigned stack_bytes)
{
    int i = 0;
    while (i < MAX_FIBERS && fibs[i].state != FREE && fibs[i].state != DONE) i++;
    if (i == MAX_FIBERS) { kestrel_log("fiber: table full"); return 0; }
    fiber *f = &fibs[i];
    if (f->state == DONE) { free(f->stack); free(f->ad); }
    memset(f, 0, sizeof *f);
    if (stack_bytes < 16384) stack_bytes = 16384;
    f->stack = malloc(stack_bytes);
    f->ad = malloc(sizeof(save_area));
    if (!f->stack || !f->ad) { free(f->stack); free(f->ad); f->stack = 0; f->ad = 0; kestrel_log("fiber: no memory"); return 0; }
    f->stack_bytes = stack_bytes;
    f->fn = fn;
    f->arg = arg;
    f->state = NEW;
    return i + 1;
}

/* The one switch point: unwind out of the running fiber, or (resumed) stop the rewind. Never inlined: binaryen
 * leaves a function that calls start_unwind / stop_rewind uninstrumented (the "runtime"), so the CALL to it is
 * where its callers unwind and rewind; inlined into kfib_block, kfib_block would be that runtime instead. */
__attribute__((noinline)) static void fib_suspend(void)
{
    if (rewinding) { asyncify_stop_rewind(); rewinding = 0; return; }
    fiber *f = &fibs[cur - 1];
    f->ad->top = f->ad->save;
    f->ad->end = f->ad->save + SAVE_BYTES;
    unwinding = 1;
    asyncify_start_unwind(f->ad);
}

static void fib_main(fiber *f) { f->fn(f->arg); }

/* Run fiber f until it suspends or returns. Not instrumented: it calls stop_unwind / start_rewind. */
__attribute__((noinline)) static void step(int i)
{
    fiber *f = &fibs[i];
    void *own_sp = sp_get();
    cur = i + 1;
    if (f->state == NEW) {
        sp_set((void *)(((uintptr_t)f->stack + f->stack_bytes) & ~(uintptr_t)15));
    } else {
        sp_set(f->sp);
        rewinding = 1;
        asyncify_start_rewind(f->ad);
    }
    f->state = BLOCKED;            /* fib_suspend's caller sets the real reason before it suspends */
    fib_main(f);
    if (unwinding) {
        asyncify_stop_unwind();
        unwinding = 0;
        f->sp = sp_get();
        unsigned used = (unsigned)((uint8_t *)f->ad->top - f->ad->save);
        if (used > save_peak) save_peak = used;
    } else {
        f->state = DONE;
    }
    sp_set(own_sp);
    cur = 0;
}

int kfib_block(kfib_ready_fn ready, void *arg, uint64_t deadline_us)
{
    if (!cur) return ready ? ready(arg) != 0 : 0;
    if (ready && ready(arg)) return 1;
    fiber *f = &fibs[cur - 1];
    f->ready = ready;
    f->rarg = arg;
    f->deadline = deadline_us;
    f->state = BLOCKED;
    fib_suspend();
    return f->woke_ready;
}

void kfib_yield(void)
{
    if (!cur) return;
    fiber *f = &fibs[cur - 1];
    f->state = YIELDED;
    f->ran_at = now_us;
    fib_suspend();
}

/* Can fiber f run now? Sets woke_ready for kfib_block. */
static int runnable(fiber *f)
{
    switch (f->state) {
    case NEW: return 1;
    case YIELDED: return f->ran_at != now_us;
    case BLOCKED:
        if (f->ready && f->ready(f->rarg)) { f->woke_ready = 1; return 1; }
        if (f->deadline && now_us >= f->deadline) { f->woke_ready = 0; return 1; }
        return 0;
    default: return 0;
    }
}

void kfib_run(unsigned passes)
{
    if (cur) return;               /* never from inside a fiber */
    for (unsigned p = 0; p < passes; p++) {
        int ran = 0;
        for (int i = 0; i < MAX_FIBERS; i++)
            if (runnable(&fibs[i])) { step(i); ran = 1; }
        if (!ran) return;
    }
}
