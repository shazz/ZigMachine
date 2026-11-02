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
    if (!gfxSetup(&appSettings.screenWidth, &appSettings.screenHeight)) { kestrel_log("chipnomad: gfxSetup failed"); return; }
    appSetup();
    running = 1;
    kestrel_log("chipnomad: booted");
    kestrel_heap_report();
}

extern "C" __attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
    // Real time (kestrel_audio.h), but at most 2 frames: ayumi costs ~4,600 cycles a sample at 44.1 kHz on the
    // board (apps/frame_cost.mjs), more than the CPU has for real time, so a longer frame would only feed the
    // mixer more and slow the UI. Until ayumi fits the budget the song plays slow on the board. (Its rate
    // cannot simply drop: ayumi steps the chip at most once a substep, so it needs rate >= clock / 64.)
    uint32_t us = kestrel_frame_us(elapsed_ms, 33);
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
    if (kestrel_quit_requested()) { running = 0; kestrel_log("chipnomad: quit"); }
}

extern "C" __attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }
extern "C" __attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
extern "C" __attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
extern "C" __attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }
