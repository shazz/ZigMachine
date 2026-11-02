/* The cart's entry points for GrafX2, which blocks in its own loops (Get_input in the main loop and in
 * every dialog). Asyncify (binaryen, run on the linked cart, see Makefile) lets it run as a coroutine:
 * kestrel_yield(), called from SDL_Delay, unwinds the whole stack back to boot()/frame(), which return to
 * the machine; the next frame() rewinds it and GrafX2 carries on after the SDL_Delay, none the wiser.
 * The unwind API is imported from "asyncify", which binaryen implements inside the module: the host
 * (browser, board) sees an ordinary cart. */
#include <stdint.h>

__attribute__((import_module("asyncify"), import_name("start_unwind"))) extern void asyncify_start_unwind(void *data);
__attribute__((import_module("asyncify"), import_name("stop_unwind"))) extern void asyncify_stop_unwind(void);
__attribute__((import_module("asyncify"), import_name("start_rewind"))) extern void asyncify_start_rewind(void *data);
__attribute__((import_module("asyncify"), import_name("stop_rewind"))) extern void asyncify_stop_rewind(void);

int grafx2_main(int argc, char *argv[]);
void kestrel_video_init(void);
void kestrel_video_frame(void);
void kestrel_sdl_vbl(void);
void kestrel_log(const char *m);
void kestrel_heap_report(void);
void kestrel_input_origin(int dx, int dy);

/* Asyncify's save area: {current, end} then the saved call stack (locals of every suspended frame). */
static uint8_t unwind_stack[64 * 1024];
static struct { void *top, *end; } adata;
static int unwinding, rewinding, suspended, finished;

static char a0[] = "grafx2", a1[] = "-mode", a2[] = "320x200";
static char *argv0[] = { a0, a1, a2, 0 };

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
    int rc = grafx2_main(3, argv0);
    if (unwinding) { asyncify_stop_unwind(); unwinding = 0; suspended = 1; return; }
    finished = 1;
    kestrel_log(rc == 0 ? "grafx2: quit" : "grafx2: exited with an error");
}

__attribute__((export_name("boot"))) void boot(void)
{
    kestrel_video_init();
    kestrel_input_origin(0, 0);
    run();
    kestrel_heap_report();
}

__attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
    kestrel_sdl_vbl();
    kestrel_video_frame();
    if (finished || !suspended) return;
    suspended = 0;
    rewinding = 1;
    asyncify_start_rewind(&adata);
    run();
}

__attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
__attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
__attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }
