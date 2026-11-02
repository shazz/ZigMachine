/* The cart's entry points for pt2-clone. boot() runs upstream's init (pt2_boot, split out of
 * pt2_main.c by split_main.py); frame() runs one pass of upstream's main loop per VBL. */
int pt2_boot(int argc, char *argv[]);
void pt2_frame(void);
#include "kestrel_audio.h"
void kestrel_sdl_vbl(uint32_t us);
void kestrel_scopes_tick(void);
void kestrel_audio_frame(uint32_t us);
void kestrel_video_init(void);
void kestrel_log(const char *m);
void kestrel_input_origin(int dx, int dy);
void kestrel_heap_report(void);

static char arg0[] = "pt2-clone";
#ifdef KESTREL_AUTOLOAD   /* test builds: make EXTRA=-DKESTREL_AUTOLOAD=RONKEN.MOD link */
#define KSTR2(x) #x
#define KSTR(x) KSTR2(x)
static char arg1[] = KSTR(KESTREL_AUTOLOAD);
static char *argv0[] = { arg0, arg1, 0 };
#define ARGC 2
#else
static char *argv0[] = { arg0, 0 };
#define ARGC 1
#endif

__attribute__((export_name("boot"))) void boot(void)
{
    kestrel_video_init();
    kestrel_input_origin(0, 28);   /* pt2 320x255 at (40,12) of the 400x280 plane; visible window at (40,40) */
    if (pt2_boot(ARGC, argv0) != 0) kestrel_log("pt2: boot failed");
    else kestrel_log("pt2: booted");
    kestrel_heap_report();
}
__attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
    /* Real time (kestrel_audio.h), up to 4 frames: pt2 mixes ~150 cycles a sample (kestrel_paula.c), so only a
     * load or a stall is ever that long. */
    uint32_t us = kestrel_frame_us(elapsed_ms, 67);
    kestrel_sdl_vbl(us);
    kestrel_scopes_tick();
    pt2_frame();
    kestrel_audio_frame(us);
}
__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }
__attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
__attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
__attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }

