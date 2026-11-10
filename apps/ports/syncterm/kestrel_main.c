/* The cart's entry points for SyncTERM. SyncTERM is threaded (its main loop, the telnet pumps, ciolib's
 * mouse thread); each thread is a fiber (../kestrel_sdl2/src/opt/kestrel_fiber.c), and frame() runs
 * every fiber that can make progress, then draws what changed (kestrel_cio.c). boot() starts SyncTERM's
 * main as the first fiber, with the fake BBS's URL on its command line, so it dials at once. */
#include <stdint.h>
#include <string.h>
#include "kestrel_fiber.h"

__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);
int syncterm_main(int argc, char **argv);
#include "kestrel_desk.h"
void kestrel_quit(void);
void kestrel_heap_report(void);

void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }

/* The frame clock is the fibers' (wasi's clock_time_get reads it through SDL_GetPerformanceCounter). */
uint64_t SDL_GetPerformanceCounter(void) { return kfib_now_us(); }
uint64_t SDL_GetPerformanceFrequency(void) { return 1000000; }
uint32_t SDL_GetTicks(void) { return (uint32_t)(kfib_now_us() / 1000); }

static char a0[] = "syncterm", a1[] = "telnet://fakebbs.zig";
static char *argv0[] = { a0, a1, 0 };
static int finished;

static void run_main(void *arg)
{
    (void)arg;
    int rc = syncterm_main(2, argv0);
    finished = 1;
    kestrel_log(rc == 0 ? "syncterm: quit" : "syncterm: exited with an error");
    kestrel_quit();   /* back to the GEM desktop (kestrel_sdl2/src/kestrel_quit.c) */
}

__attribute__((export_name("boot"))) void boot(void)
{
    kestrel_desk_boot();
    if (kestrel_desk_on()) kestrel_desk_status(" SyncTERM 1.9 - telnet://fakebbs.zig - network: MOCK (an in-cart BBS, no TCP/IP)");
    if (!kfib_spawn(run_main, 0, 256 * 1024)) { kestrel_log("syncterm: no fiber for main"); return; }
    kfib_run(64);
    kestrel_heap_report();
}

__attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
    (void)elapsed_ms;
    kfib_tick(1000000 / 60);
    if (!finished) kfib_run(64);
    kestrel_desk_frame();
}

__attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }
__attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
__attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }
