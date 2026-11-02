/* SDL timers and mutexes on the cart, which has no threads. Opt-in (src/opt).
 *
 * Timers: SDL runs a timer callback on its own thread; here the port calls kestrel_timers_tick(now_ms) once a
 * frame (with its SDL_GetTicks clock) and every due timer fires there, at most once per tick (a 500 ms key
 * repeat at 60 Hz is late by under 17 ms). A callback returns its next interval; 0 removes the timer.
 * Mutexes: with one thread nothing can contend, so they are distinct non-NULL no-ops. */
#include <SDL2/SDL.h>

void kestrel_log(const char *m);

#define MAX_TIMERS 16
static struct { SDL_TimerID id; Uint32 interval, due; SDL_TimerCallback cb; void *param; } timers[MAX_TIMERS];
static SDL_TimerID next_id = 1;
static Uint32 now;

SDL_TimerID SDL_AddTimer(Uint32 interval, SDL_TimerCallback cb, void *param)
{
    if (!cb) return 0;
    for (int i = 0; i < MAX_TIMERS; i++) {
        if (timers[i].id) continue;
        timers[i].id = next_id++;
        timers[i].interval = interval;
        timers[i].due = now + interval;
        timers[i].cb = cb;
        timers[i].param = param;
        return timers[i].id;
    }
    kestrel_log("SDL_AddTimer: no free timer slot");
    return 0;
}

SDL_bool SDL_RemoveTimer(SDL_TimerID id)
{
    if (!id) return SDL_FALSE;
    for (int i = 0; i < MAX_TIMERS; i++) if (timers[i].id == id) { timers[i].id = 0; return SDL_TRUE; }
    return SDL_FALSE;
}

void kestrel_timers_tick(Uint32 now_ms)
{
    now = now_ms;
    for (int i = 0; i < MAX_TIMERS; i++) {
        if (!timers[i].id || (Sint32)(now - timers[i].due) < 0) continue;
        SDL_TimerID id = timers[i].id;
        Uint32 next = timers[i].cb(timers[i].interval, timers[i].param);
        if (timers[i].id != id) continue;            /* the callback removed (or replaced) it */
        if (next == 0) { timers[i].id = 0; continue; }
        timers[i].interval = next;
        timers[i].due = now + next;
    }
}

static char mutex_handle;
SDL_mutex *SDL_CreateMutex(void) { return (SDL_mutex *)&mutex_handle; }
void SDL_DestroyMutex(SDL_mutex *m) { (void)m; }
int SDL_LockMutex(SDL_mutex *m) { (void)m; return 0; }
int SDL_UnlockMutex(SDL_mutex *m) { (void)m; return 0; }
