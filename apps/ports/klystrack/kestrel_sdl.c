/* The SDL2 calls klystrack makes that the shared layer does not provide (apps/ports/kestrel_sdl2: src/ for
 * input, heap and WASI-on-floppy; src/opt/ for RWops, the software renderer, the plane presenter, timers,
 * stb_image and key names). What is left here is klystrack-shaped: the clock, the window, the audio device.
 *
 * Time: the frame's real time (kestrel_audio.h: hostMicros, else dt), advanced by kestrel_sdl_vbl(); SDL_Delay()
 * yields the frame (kestrel_main.c).
 * Window: fixed 320x240 (patches/mused.c.sed makes that klystrack's default size).
 * Audio: klystron's cyd opens the legacy SDL_OpenAudio device with its mixing callback; kestrel_audio_frame()
 * runs the callback for the frame's real time (kestrel_audio_pump) and feeds the machine's stream. */
#include <SDL2/SDL.h>
#include "kestrel_audio.h"

__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);
void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }
void kestrel_yield(void);
void kestrel_timers_tick(Uint32 now_ms);

#define WIN_W 320
#define WIN_H 240

/* --- core --- */
int SDL_Init(Uint32 flags) { (void)flags; return 0; }
void SDL_Quit(void) {}
const char *SDL_GetError(void) { return "KESTREL: not supported"; }
void SDL_GetVersion(SDL_version *v) { SDL_VERSION(v); }
SDL_bool SDL_SetHint(const char *n, const char *v) { (void)n; (void)v; return SDL_TRUE; }
int SDL_setenv(const char *n, const char *v, int o) { (void)n; (void)v; (void)o; return 0; }
char *SDL_getenv(const char *n) { (void)n; return NULL; }
char *SDL_GetBasePath(void) { char *s = malloc(2); if (s) strcpy(s, "/"); return s; }
int SDL_ShowSimpleMessageBox(Uint32 f, const char *t, const char *m, SDL_Window *w) { (void)f; (void)w; kestrel_log(t); kestrel_log(m); return 0; }
SDL_bool SDL_HasSSE(void) { return SDL_FALSE; }
SDL_bool SDL_HasSSE2(void) { return SDL_FALSE; }
Uint8 SDL_EventState(Uint32 t, int s) { (void)t; (void)s; return SDL_ENABLE; }
void SDL_PumpEvents(void) {}

/* --- time --- */
static Uint64 micros;
void kestrel_sdl_vbl(Uint32 us) { micros += us; kestrel_timers_tick((Uint32)(micros / 1000)); }
Uint32 SDL_GetTicks(void) { return (Uint32)(micros / 1000); }
Uint64 SDL_GetPerformanceCounter(void) { return micros; }
Uint64 SDL_GetPerformanceFrequency(void) { return 1000000; }
void SDL_Delay(Uint32 ms) { (void)ms; kestrel_yield(); }

/* --- window: one fixed 320x240 window --- */
static char window_handle;
SDL_Window *SDL_CreateWindow(const char *t, int x, int y, int w, int h, Uint32 f) { (void)t; (void)x; (void)y; (void)w; (void)h; (void)f; return (SDL_Window *)&window_handle; }
void SDL_DestroyWindow(SDL_Window *w) { (void)w; }
Uint32 SDL_GetWindowFlags(SDL_Window *w) { (void)w; return SDL_WINDOW_INPUT_FOCUS; }
void SDL_GetWindowSize(SDL_Window *w, int *ww, int *hh) { (void)w; if (ww) *ww = WIN_W; if (hh) *hh = WIN_H; }
void SDL_SetWindowSize(SDL_Window *w, int ww, int hh) { (void)w; (void)ww; (void)hh; }
void SDL_SetWindowMinimumSize(SDL_Window *w, int ww, int hh) { (void)w; (void)ww; (void)hh; }
void SDL_SetWindowTitle(SDL_Window *w, const char *t) { (void)w; (void)t; }
void SDL_SetWindowIcon(SDL_Window *w, SDL_Surface *s) { (void)w; (void)s; }
int SDL_SetWindowFullscreen(SDL_Window *w, Uint32 f) { (void)w; (void)f; return 0; }

/* --- audio: the legacy device --- */
/* The ring's head start: klystrack runs ~7 fps on the board (143 ms a frame), and the speaker must not
 * catch the feed up between two frames. */
#define AUDIO_LEAD_MS 200
static SDL_AudioSpec spec;
static int audio_open, audio_paused = 1;

int SDL_OpenAudio(SDL_AudioSpec *want, SDL_AudioSpec *have)
{
    if (!want || !want->callback || want->freq <= 0) { kestrel_log("SDL_OpenAudio: unsupported spec"); return -1; }
    spec = *want;
    spec.format = AUDIO_S16SYS; spec.channels = 2; spec.samples = (Uint16)(want->freq / 60);
    if (have) *have = spec;
    audio_open = 1;
    return 0;
}
void SDL_PauseAudio(int p) { audio_paused = p; }
void SDL_CloseAudio(void) { audio_open = 0; }

static void mix(void *ctx, int16_t *stereo, int frames)
{
    (void)ctx;
    if (audio_paused) memset(stereo, 0, (size_t)frames * 4);
    else spec.callback(spec.userdata, (Uint8 *)stereo, frames * 4);
}

/* Once a frame: cyd's callback (the song's clock too) for the real time the frame took. */
void kestrel_audio_frame(Uint32 us)
{
    if (audio_open) kestrel_audio_pump(us, (Uint32)spec.freq, AUDIO_LEAD_MS, mix, NULL);
}
