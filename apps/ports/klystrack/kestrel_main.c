/* The cart's entry points for klystrack, which blocks in its own loops (the main loop sleeps in SDL_Delay; the
 * message boxes, file dialogs and help screen have loops of their own). As GrafX2 (apps/ports/grafx2):
 * binaryen's Asyncify, run on the linked cart (Makefile), turns it into a coroutine. kestrel_yield(), called
 * from SDL_Delay and after every SDL_RenderPresent, unwinds the whole stack back to boot()/frame(), which return
 * to the machine; the next frame() rewinds it and klystrack carries on, none the wiser. The unwind API is
 * imported from "asyncify", which binaryen implements inside the module: the host sees an ordinary cart.
 *
 * Each frame(): the clock (the frame's real time, kestrel_audio.h), SDL timers (key repeat, info line), one VBL of audio (cyd's callback), then
 * klystrack runs until its next yield (one main-loop pass: draw + present, or a 4 ms idle sleep). */
#include <stdint.h>

__attribute__((import_module("asyncify"), import_name("start_unwind"))) extern void asyncify_start_unwind(void *data);
__attribute__((import_module("asyncify"), import_name("stop_unwind"))) extern void asyncify_stop_unwind(void);
__attribute__((import_module("asyncify"), import_name("start_rewind"))) extern void asyncify_start_rewind(void *data);
__attribute__((import_module("asyncify"), import_name("stop_rewind"))) extern void asyncify_stop_rewind(void);

int klystrack_main(int argc, char *argv[]);
#include "kestrel_audio.h"
void kestrel_sdl_vbl(uint32_t us);
void kestrel_audio_frame(uint32_t us);
void kestrel_plane_init(void);
void kestrel_log(const char *m);
void kestrel_quit(void);
void kestrel_heap_report(void);
void kestrel_input_origin(int dx, int dy);
extern void (*kestrel_present_hook)(void);
void kestrel_after_present(void);
void kestrel_plane_cursor(void);
void kestrel_input_wake(void);
static int presented;
void kestrel_yield(void);

/* SDL_RenderPresent's hook: note the picture (kestrel_sdl.c: a changed one keeps the repaints going), yield. */
static void after_present(void) { presented = 1; kestrel_after_present(); kestrel_yield(); }

/* Asyncify's save area: {current, end} then the saved call stack (locals of every suspended frame). */
static uint8_t unwind_stack[64 * 1024];
static struct { void *top, *end; } adata;
static int unwinding, rewinding, suspended, finished;

/* argv[1]: the song klystrack opens at start (main.c: fopen(argv[1]) -> open_song), from the floppy. */
static char a0[] = "klystrack", a1[] = "STARPRT2.KT";
static char *argv0[] = { a0, a1, 0 };

void kestrel_yield(void)
{
    if (rewinding) { asyncify_stop_rewind(); rewinding = 0; return; }   /* resumed: carry on */
    adata.top = unwind_stack;
    adata.end = unwind_stack + sizeof unwind_stack;
    unwinding = 1;
    asyncify_start_unwind(&adata);
}

static void run(void)
{
    int rc = klystrack_main(2, argv0);
    if (unwinding) { asyncify_stop_unwind(); unwinding = 0; suspended = 1; return; }
    finished = 1;
    kestrel_log(rc == 0 ? "klystrack: quit" : "klystrack: exited with an error");
    kestrel_quit();   /* main returned: back to the GEM desktop (kestrel_sdl2/src/kestrel_quit.c) */
}

__attribute__((export_name("boot"))) void boot(void)
{
    kestrel_plane_init();
    kestrel_input_origin(0, 20);   /* 320x240 at (40,20) of the 400x280 plane; the visible window starts at (40,40) */
    kestrel_present_hook = after_present;
    run();
    kestrel_log(finished ? "klystrack: did not reach its main loop" : "klystrack: booted");
    kestrel_heap_report();
}

__attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
    /* Real time (kestrel_audio.h), but at most 2 frames: cyd costs ~13,000 cycles a sample at 22.05 kHz on the
     * board (apps/frame_cost.mjs), more than the CPU has for real time, so a longer frame would only feed the
     * mixer more and slow the UI to ~1 fps. Until cyd fits the budget the song plays slow on the board. */
    uint32_t us = kestrel_frame_us(elapsed_ms, 33);
    kestrel_sdl_vbl(us);
    kestrel_audio_frame(us);
    if (finished || !suspended) return;
    suspended = 0;
    kestrel_input_wake();
    rewinding = 1;
    presented = 0;
    asyncify_start_rewind(&adata);
    run();
    if (!presented) kestrel_plane_cursor();   /* no repaint this frame: the pointer still follows the mouse */
}

__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }
__attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
__attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
__attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }
