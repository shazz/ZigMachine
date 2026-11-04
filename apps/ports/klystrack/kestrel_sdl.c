/* The SDL2 calls klystrack makes that the shared layer does not provide (apps/ports/kestrel_sdl2: src/ for
 * input, heap and WASI-on-floppy; src/opt/ for RWops, the software renderer, the plane presenter, timers,
 * stb_image and key names). What is left here is klystrack-shaped: the clock, the window, the audio device.
 *
 * Time: the frame's real time (kestrel_audio.h: hostMicros, else dt), advanced by kestrel_sdl_vbl(); SDL_Delay()
 * yields the frame (kestrel_main.c).
 * Window: fixed 320x240 (patches/mused.c.sed makes that klystrack's default size).
 * Audio: klystron's cyd opens the legacy SDL_OpenAudio device with its mixing callback; kestrel_audio_frame()
 * runs the callback for the frame's real time (kestrel_audio_pump) and feeds the machine's stream; a song that
 * plays is handed to the machine's .kt player instead, cyd keeping only its sequencer (kestrel_bard.c). */
#include <SDL2/SDL.h>
#include "kestrel_audio.h"
#include "snd/cyd.h"
#include "snd/music.h"

__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);
void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }
void kestrel_yield(void);
void kestrel_timers_tick(Uint32 now_ms);

#define WIN_W 320
#define WIN_H 240

/* --- core --- */
int SDL_Init(Uint32 flags) { (void)flags; return 0; }
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

/* cyd at rest: no song (the tick callback has none, or is off), every channel's gate off and envelope at 0,
 * and the output exactly 0 for longer than the longest echo (the reverb's 2 s delay line, no feedback; the
 * chorus's 50 ms). Then the callback would only compute silence (8 channels, ~2.4 Mc a frame): it is skipped
 * and zeros are fed until a note or a song starts (keyjazz gates a channel; play sets the song). */
#define QUIET_AFTER_MS 2200
/* At boot nothing has sounded, so nothing can echo: cyd starts at rest (it mixed 2.2 s of exact silence
 * first, ~2.2 Mc a frame for the first 132 frames: most of the board's 5 s at 5 fps after loading). */
static Uint32 rest_samples = 0x40000000u;

static int cyd_busy(void)
{
    const CydEngine *cyd = spec.userdata;
    const MusEngine *mus = cyd->callback ? cyd->callback_parameter : NULL;
    if (mus && mus->song) return 1;
    for (int i = 0; i < cyd->n_channels; i++)
        if ((cyd->channel[i].flags & CYD_CHN_ENABLE_GATE) || cyd->channel[i].adsr.envelope) return 1;
    return 0;
}

int kestrel_bard_mix(CydEngine *cyd, int16_t *stereo, int frames); /* kestrel_bard.c */

static void mix(void *ctx, int16_t *stereo, int frames)
{
    (void)ctx;
    if (audio_paused) { memset(stereo, 0, (size_t)frames * 4); return; }
    if (kestrel_bard_mix(spec.userdata, stereo, frames)) return; /* the song plays on the machine's .kt player */
    if (cyd_busy()) rest_samples = 0;
    else if (rest_samples >= spec.freq / 1000 * QUIET_AFTER_MS) { memset(stereo, 0, (size_t)frames * 4); return; }
    spec.callback(spec.userdata, (Uint8 *)stereo, frames * 4);
    const Uint32 *w = (const Uint32 *)stereo;
    for (int i = 0; i < frames; i++) if (w[i]) { rest_samples = 0; return; }
    rest_samples += (Uint32)frames;
}

/* --- redraws (patches/main.c.sed) ---
 * Upstream repaints the whole UI 30 times a second whatever happens (gfx_domain_is_next_frame): ~45 Mc a
 * repaint on the board. Here the 30 Hz repaint runs only while something moves: a song plays, or one of the
 * last SETTLE repaints changed the picture (VU meters falling, a keyjazz note's scope), or an SDL timer fired
 * (the info line clears itself after 5 s). An event (key, click, drag) still repaints at once, as upstream. */
#define SETTLE 15
static int settle = SETTLE;
unsigned kestrel_timers_fired(void);
int kestrel_plane_changed(void);

int kestrel_redraw_due(int tick_due, int playing)
{
    static unsigned fired;
    unsigned f = kestrel_timers_fired();
    if (playing || f != fired) settle = SETTLE;
    fired = f;
    if (!tick_due || settle <= 0) return 0;
    settle--;
    return 1;
}

/* Once a frame before klystrack runs: a queued key, button, wheel or drag wakes the repaints, so a dialog opened
 * by it (its own loop repaints on the same 30 Hz tick, patches/msgbox.c.sed, help.c.sed) is drawn. A plain
 * pointer move does not: kestrel_plane_cursor() moves the pointer without a repaint, as upstream does. */
void kestrel_input_wake(void)
{
    SDL_Event q[16];
    int n = SDL_PeepEvents(q, 16, SDL_PEEKEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT);
    for (int i = 0; i < n; i++)
        if (q[i].type != SDL_MOUSEMOTION || q[i].motion.state) { settle = SETTLE; return; }
}

/* After each present: a repaint that changed the picture keeps the 30 Hz repaints going. */
void kestrel_after_present(void) { if (kestrel_plane_changed()) settle = SETTLE; }

/* Once a frame: cyd's callback (the song's clock too) for the real time the frame took. */
void kestrel_audio_frame(Uint32 us)
{
    if (audio_open) kestrel_audio_pump(us, (Uint32)spec.freq, AUDIO_LEAD_MS, mix, NULL);
}
