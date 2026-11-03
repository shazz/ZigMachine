// The cart's entry points for ChipNomad: upstream's main() (platforms/shared/main.cpp) up to mainLoopRun runs in
// boot(); one pass of the SDL2 main loop (events, tick, draw) runs per frame().
#include <SDL2/SDL.h>
#include "corelib_gfx.h"
#include "corelib_font.h"
#include "corelib_mainloop.h"
#include "app.h"
#include "common.h"
#include "kestrel_audio.h"

extern "C" {
void kestrel_log(const char *m);
void kestrel_gfx_frame(void);
void kestrel_audio_frame(uint32_t us);
void kestrel_sdl_vbl(uint32_t us);
void kestrel_heap_report(void);
int kestrel_quit_requested(void);
void kestrel_quit(void);
void kestrel_input_origin(int dx, int dy);
}

static int running;
// C++ static constructors: a cart has no _start (--no-entry), so boot() runs them itself, once.
extern "C" void __wasm_call_ctors(void);

extern "C" __attribute__((export_name("boot"))) void boot(void)
{
    __wasm_call_ctors();
    kestrel_input_origin(0, 0);
    settingsLoad();
    // 22.05 kHz: kestrel_ayumi.cpp works at any rate (upstream's ayumi needed >= clock / 64), and the stream
    // ends as 8-bit mono anyway; half of 44.1 kHz halves the synth's cost a second.
    appSettings.audioSampleRate = 22050;
    if (!gfxSetup(&appSettings.screenWidth, &appSettings.screenHeight)) { kestrel_log("chipnomad: gfxSetup failed"); return; }
    appSetup();
    running = 1;
    kestrel_log("chipnomad: booted");
    kestrel_heap_report();
}

extern "C" __attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
    // Real time (kestrel_audio.h), at most 4 frames (a stall, as pt2): the integer ayumi (kestrel_ayumi.cpp)
    // costs a few hundred cycles a 22.05 kHz sample, well inside real time on the board.
    uint32_t us = kestrel_frame_us(elapsed_ms, 67);
    kestrel_sdl_vbl(us);
    kestrel_gfx_frame();
    if (!running) return;
    SDL_Event e;
    MainLoopEventData d;
    while (SDL_PollEvent(&e)) {
        if (e.type != SDL_KEYDOWN && e.type != SDL_KEYUP) continue;
        d.type = e.type == SDL_KEYDOWN ? MainLoopEvent::keyDown : MainLoopEvent::keyUp;
        d.data.input = (InputCode){InputDeviceType::keyboard, e.key.keysym.sym};
        appOnEvent(d);
    }
    d.type = MainLoopEvent::tick;
    d.data.value = 0;
    appOnEvent(d);
    appDraw();
    kestrel_audio_frame(us);
    // Settings > Quit ChipNomad (mainLoopTriggerQuit): back to the GEM desktop (kestrel_sdl2/src/kestrel_quit.c).
    if (kestrel_quit_requested()) { running = 0; kestrel_log("chipnomad: quit"); kestrel_quit(); }
}

extern "C" __attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }
extern "C" __attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
extern "C" __attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
extern "C" __attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }
