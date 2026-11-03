/* The SDL2 subset pt2-clone uses, on the ZigMachine.
 *
 * Step 1 (this file today): every call links and returns something sane, so the cart boots.
 * The five real backends still to write (README.md "Plan"):
 *   video  SDL_UpdateTexture/RenderPresent -> the 320x255 ARGB frameBuffer, indexed onto an 8-bit plane
 *   input  SDL_PollEvent / GetMouseState / GetModState  <- the cart input ABI (keyboard + mouse)
 *   audio  SDL_OpenAudioDevice: keep the callback; frame() calls it for the frame's real time -> PCM stream
 *   time   SDL_GetPerformanceCounter: the same real time (kestrel_audio.h: hostMicros, else dt)
 *   threads SDL_CreateThread: run the job inline (mod2wav / pat2smp) or refuse it
 * Everything window-, renderer-, cursor- and hint-shaped stays a no-op. */
#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>
#include "kestrel_audio.h"

/* Distinct non-NULL handles: pt2 only checks them against NULL. */
static char window_handle, renderer_handle, texture_handle, cursor_handle;
static SDL_PixelFormat argb = { SDL_PIXELFORMAT_ARGB8888 };

/* --- core --- */
int SDL_Init(Uint32 flags) { (void)flags; return 0; }
const char *SDL_GetError(void) { return "KESTREL: not supported"; }
void SDL_GetVersion(SDL_version *v) { SDL_VERSION(v); }
SDL_bool SDL_SetHint(const char *n, const char *v) { (void)n; (void)v; return SDL_TRUE; }
void SDL_Delay(Uint32 ms) { (void)ms; } /* the cart never blocks: frame() returns instead */
__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);
__attribute__((import_module("env"), import_name("hwVideoBase"))) extern int hwVideoBase(void);
void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }
int SDL_ShowSimpleMessageBox(Uint32 f, const char *t, const char *m, SDL_Window *w) { (void)f; (void)w; kestrel_log(t); kestrel_log(m); return 0; }

/* --- time --- */
static Uint64 ticks; /* advanced by kestrel_sdl_vbl(): the frame's real time, as the audio (kestrel_audio.h) */
void kestrel_sdl_vbl(Uint32 us) { ticks += us; }
Uint64 SDL_GetPerformanceCounter(void) { return ticks; }
Uint64 SDL_GetPerformanceFrequency(void) { return 1000000; }

/* --- threads --- */
/* No threads on the cart. pt2's threads are finite jobs (the disk op file lister, mod2wav) except the
 * scope loop, which pt2_scopes.c.sed turns into a per-frame tick; so a "thread" runs to completion here. */
static char thread_handle;
SDL_Thread *SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data) { (void)name; fn(data); return (SDL_Thread *)&thread_handle; }
void SDL_DetachThread(SDL_Thread *t) { (void)t; }
int SDL_SetThreadPriority(SDL_ThreadPriority p) { (void)p; return 0; }

/* --- window --- */
SDL_Window *SDL_CreateWindow(const char *t, int x, int y, int w, int h, Uint32 f) { (void)t; (void)x; (void)y; (void)w; (void)h; (void)f; return (SDL_Window *)&window_handle; }
void SDL_DestroyWindow(SDL_Window *w) { (void)w; }
Uint32 SDL_GetWindowFlags(SDL_Window *w) { (void)w; return SDL_WINDOW_INPUT_FOCUS; }
void SDL_GetWindowSize(SDL_Window *w, int *ww, int *hh) { (void)w; if (ww) *ww = 320; if (hh) *hh = 255; }
void SDL_GL_GetDrawableSize(SDL_Window *w, int *ww, int *hh) { SDL_GetWindowSize(w, ww, hh); }
void SDL_GetWindowPosition(SDL_Window *w, int *x, int *y) { (void)w; if (x) *x = 0; if (y) *y = 0; }
int SDL_GetWindowDisplayIndex(SDL_Window *w) { (void)w; return 0; }
int SDL_GetDesktopDisplayMode(int i, SDL_DisplayMode *dm) { (void)i; dm->format = SDL_PIXELFORMAT_ARGB8888; dm->w = 320; dm->h = 255; dm->refresh_rate = 60; dm->driverdata = NULL; return 0; }
void SDL_SetWindowTitle(SDL_Window *w, const char *t) { (void)w; (void)t; }
int SDL_SetWindowFullscreen(SDL_Window *w, Uint32 f) { (void)w; (void)f; return 0; }
void SDL_ShowWindow(SDL_Window *w) { (void)w; }
void SDL_RaiseWindow(SDL_Window *w) { (void)w; }
void SDL_RestoreWindow(SDL_Window *w) { (void)w; }
void SDL_EnableScreenSaver(void) {}
SDL_bool SDL_GetWindowWMInfo(SDL_Window *w, SDL_SysWMinfo *i) { (void)w; (void)i; return SDL_FALSE; }

/* --- video: pt2's 320x255 ARGB frameBuffer -> plane 0, FB_MODE_FULLSCREEN (400x280), centred ---
 * Colours are indexed on first sight (pt2 uses a few dozen): a 512-slot open hash ARGB -> index,
 * each new colour written once into palette 0. */
#define REG_BACKGROUND 0x04
#define REG_FB_STRIDE 0x34
#define REG_FB_BASE 0x44
#define REG_FB_MODE 0x54
#define OFF_PAL 0x0100
#define OFF_VRAM 0x1100
#define FB_MODE_FULLSCREEN 1
#define PW 400
#define PH 280
#define SW 320
#define SH 255
#define OX ((PW - SW) / 2)
#define OY ((PH - SH) / 2)
static const void *present_src;
static Uint8 *vbase;
static Uint32 hkey[512];
static Uint8 hval[512], hused[512];
static unsigned ncolours;
static Uint32 pal_rgb[256]; /* index -> ARGB, rewritten into palette 0 every present (the host may reset it) */
static int overflow_logged;

static Uint8 colour_index(Uint32 c);

void kestrel_video_init(void)
{
    vbase = (Uint8 *)(uintptr_t)hwVideoBase();
    *(Uint32 *)(vbase + REG_BACKGROUND) = 0xFF000000u;
    *(Uint16 *)(vbase + REG_FB_STRIDE) = PW;
    *(Uint32 *)(vbase + REG_FB_BASE) = OFF_VRAM;
    vbase[REG_FB_MODE] = FB_MODE_FULLSCREEN;
    memset(vbase + OFF_VRAM, 0, PW * PH);
    (void)colour_index(0xFF000000u); /* index 0 = black: the plane's margins around pt2's 320x255 */
}

static Uint8 colour_index(Uint32 c)
{
    c |= 0xFF000000u;
    unsigned h = (c * 2654435761u) >> 23;
    while (hused[h]) { if (hkey[h] == c) return hval[h]; h = (h + 1) & 511; }
    if (ncolours >= 256) {
        if (!overflow_logged) { kestrel_log("pt2: more than 256 colours, extras drawn as index 0"); overflow_logged = 1; }
        return 0;
    }
    Uint8 i = (Uint8)ncolours++;
    hused[h] = 1; hkey[h] = c; hval[h] = i;
    pal_rgb[i] = c;
    return i;
}

/* The rectangles pt2 drew since the last present, as a column range per row (x1 exclusive; empty: x1 <= x0).
 * Every frameBuffer write site marks its rectangle (kestrel_port.h, patches/*.sed), so a present converts only
 * those: idle, pt2 redraws the scopes, the VU meters and the pointer sprite (~1/5 of the screen), and reading
 * the whole 326 KB ARGB picture cost ~1.7 Mc a frame on the board (frame_cost: a D$ miss every 8 pixels). */
static Uint16 dirty_x0[SH], dirty_x1[SH];
static int all_dirty = 1; /* the first present converts everything */

void kestrel_fb_dirty(int32_t x, int32_t y, int32_t w, int32_t h)
{
    int32_t x1 = x + w, y1 = y + h;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x1 > SW) x1 = SW;
    if (y1 > SH) y1 = SH;
    if (x >= x1) return;
    for (; y < y1; y++) {
        if (dirty_x1[y] <= dirty_x0[y]) { dirty_x0[y] = (Uint16)x; dirty_x1[y] = (Uint16)x1; continue; }
        if (x < dirty_x0[y]) dirty_x0[y] = (Uint16)x;
        if (x1 > dirty_x1[y]) dirty_x1[y] = (Uint16)x1;
    }
}

/* Words w0 .. w1-1 of row y: four pixels a word (little-endian, pixel x + k at byte k), a run in one compare. */
static void convert_row(const Uint32 *src, int y, int w0, int w1)
{
    static Uint32 last = ~0u;
    static Uint8 li;
    Uint32 *dst = (Uint32 *)(void *)(vbase + OFF_VRAM + (OY + y) * PW + OX);
    src += y * SW + w0 * 4;
    for (int x = w0; x < w1; x++, src += 4) {
        Uint32 w;
        if (src[0] == last && src[1] == last && src[2] == last && src[3] == last) { /* a run: most of the screen */
            w = li * 0x01010101u;
        } else {
            w = 0;
            for (int k = 0; k < 4; k++) {
                Uint32 c = src[k];
                if (c != last) { last = c; li = colour_index(c); }
                w |= (Uint32)li << (8 * k);
            }
        }
        dst[x] = w;
    }
}

#ifdef KESTREL_PRESENT_CHECK
/* Test builds (make EXTRA=-DKESTREL_PRESENT_CHECK): a write site that marks nothing shows up as a row the
 * dirty present left different from a full one. */
static void check_present(const Uint32 *src)
{
    static int reported;
    for (int y = 0; y < SH && reported < 20; y++) {
        const Uint8 *d = vbase + OFF_VRAM + (OY + y) * PW + OX;
        for (int x = 0; x < SW; x++) {
            if (pal_rgb[d[x]] == (src[y * SW + x] | 0xFF000000u)) continue;
            char m[96];
            snprintf(m, sizeof m, "pt2 present check: row %d x %d stale (a write site marked nothing)", y, x);
            kestrel_log(m);
            reported++;
            break;
        }
    }
}
#endif

static void present(void)
{
    if (!present_src || !vbase) return;
    const Uint32 *src = present_src;
    for (int y = 0; y < SH; y++) {
        if (all_dirty) convert_row(src, y, 0, SW / 4);
        else if (dirty_x1[y] > dirty_x0[y]) convert_row(src, y, dirty_x0[y] >> 2, (dirty_x1[y] + 3) >> 2);
        dirty_x0[y] = dirty_x1[y] = 0;
    }
    all_dirty = 0;
#ifdef KESTREL_PRESENT_CHECK
    check_present(src);
#endif
    for (unsigned i = 0; i < ncolours; i++) {
        Uint8 *p = vbase + OFF_PAL + i * 4;
        Uint32 c = pal_rgb[i];
        p[0] = (Uint8)(c >> 16); p[1] = (Uint8)(c >> 8); p[2] = (Uint8)c; p[3] = 255;
    }
    vbase[REG_FB_MODE] = FB_MODE_FULLSCREEN; /* re-assert the plane setup too */
    *(Uint16 *)(vbase + REG_FB_STRIDE) = PW;
    *(Uint32 *)(vbase + REG_FB_BASE) = OFF_VRAM;
}

/* --- renderer / texture --- */
SDL_Renderer *SDL_CreateRenderer(SDL_Window *w, int i, Uint32 f) { (void)w; (void)i; (void)f; return (SDL_Renderer *)&renderer_handle; }
void SDL_DestroyRenderer(SDL_Renderer *r) { (void)r; }
int SDL_SetRenderDrawColor(SDL_Renderer *r, Uint8 a, Uint8 b, Uint8 c, Uint8 d) { (void)r; (void)a; (void)b; (void)c; (void)d; return 0; }
int SDL_SetRenderDrawBlendMode(SDL_Renderer *r, SDL_BlendMode m) { (void)r; (void)m; return 0; }
int SDL_RenderClear(SDL_Renderer *r) { (void)r; return 0; }
int SDL_RenderCopy(SDL_Renderer *r, SDL_Texture *t, const SDL_Rect *s, const SDL_Rect *d) { (void)r; (void)t; (void)s; (void)d; return 0; }
void SDL_RenderPresent(SDL_Renderer *r) { (void)r; present(); }
SDL_Texture *SDL_CreateTexture(SDL_Renderer *r, Uint32 f, int a, int w, int h) { (void)r; (void)f; (void)a; (void)w; (void)h; return (SDL_Texture *)&texture_handle; }
void SDL_DestroyTexture(SDL_Texture *t) { (void)t; }
int SDL_SetTextureBlendMode(SDL_Texture *t, SDL_BlendMode m) { (void)t; (void)m; return 0; }
int SDL_UpdateTexture(SDL_Texture *t, const SDL_Rect *r, const void *px, int pitch) { (void)t; (void)r; (void)pitch; present_src = px; return 0; }

/* --- surfaces: only the mouse pointer sprite uses them --- */
SDL_Surface *SDL_CreateRGBSurface(Uint32 f, int w, int h, int d, Uint32 rm, Uint32 gm, Uint32 bm, Uint32 am)
{
    (void)f; (void)d; (void)rm; (void)gm; (void)bm; (void)am;
    SDL_Surface *s = calloc(1, sizeof *s);
    if (s == NULL) return NULL;
    s->pixels = calloc((size_t)w * (size_t)h, 4);
    if (s->pixels == NULL) { free(s); return NULL; }
    s->format = &argb; s->w = w; s->h = h; s->pitch = w * 4;
    return s;
}
void SDL_FreeSurface(SDL_Surface *s) { if (s) { free(s->pixels); free(s); } }
int SDL_LockSurface(SDL_Surface *s) { (void)s; return 0; }
void SDL_UnlockSurface(SDL_Surface *s) { (void)s; }
int SDL_SetColorKey(SDL_Surface *s, int f, Uint32 k) { (void)s; (void)f; (void)k; return 0; }
int SDL_SetSurfaceRLE(SDL_Surface *s, int f) { (void)s; (void)f; return 0; }
int SDL_SetSurfaceBlendMode(SDL_Surface *s, SDL_BlendMode m) { (void)s; (void)m; return 0; }
Uint32 SDL_MapRGB(const SDL_PixelFormat *f, Uint8 r, Uint8 g, Uint8 b) { (void)f; return 0xFF000000u | (Uint32)r << 16 | (Uint32)g << 8 | b; }

/* --- mouse: state and events are in kestrel_input.c --- */
void SDL_WarpMouseInWindow(SDL_Window *w, int x, int y) { (void)w; (void)x; (void)y; }
int SDL_ShowCursor(int t) { (void)t; return 0; }
SDL_Cursor *SDL_CreateColorCursor(SDL_Surface *s, int x, int y) { (void)s; (void)x; (void)y; return (SDL_Cursor *)&cursor_handle; }
SDL_Cursor *SDL_GetDefaultCursor(void) { return (SDL_Cursor *)&cursor_handle; }
void SDL_SetCursor(SDL_Cursor *c) { (void)c; }
void SDL_FreeCursor(SDL_Cursor *c) { (void)c; }

/* --- keyboard / events: kestrel_input.c --- */
Uint8 SDL_EventState(Uint32 t, int s) { (void)t; (void)s; return SDL_ENABLE; }

/* --- audio --- */
/* 24 kHz: the mixer (kestrel_paula.c) point-samples Paula, so any rate keeps the pitch; the stream is
 * 8-bit mono, and 24 kHz keeps everything up to 12 kHz (pt2's A500 filter is at 4.4 kHz, its LED at
 * 3.1 kHz) for half of 48 kHz's mixing. 400 samples a 60 Hz frame. */
#define AUDIO_RATE 24000
#define AUDIO_LEAD_MS 125 /* the ring's head start: pt2 runs ~25 fps on the board while a module plays */
static SDL_AudioSpec spec;
SDL_AudioDeviceID SDL_OpenAudioDevice(const char *d, int cap, const SDL_AudioSpec *want, SDL_AudioSpec *have, int allowed)
{
    (void)d; (void)cap; (void)allowed;
    spec = *want;
    /* samples: the latency pt2 delays its pattern cursor and scopes by (calcAudioLatencyVars), the ring lead */
    spec.freq = AUDIO_RATE; spec.format = AUDIO_S16; spec.channels = 2; spec.samples = AUDIO_RATE * AUDIO_LEAD_MS / 1000;
    if (have) *have = spec;
    return 1;
}
void SDL_CloseAudioDevice(SDL_AudioDeviceID d) { (void)d; spec.callback = NULL; }
static int audio_paused = 1;
void SDL_PauseAudioDevice(SDL_AudioDeviceID d, int p) { (void)d; audio_paused = p; }

static void mix(void *ctx, int16_t *stereo, int frames)
{
    (void)ctx;
    if (audio_paused || !spec.callback) memset(stereo, 0, (size_t)frames * 4);
    else spec.callback(spec.userdata, (Uint8 *)stereo, frames * 4);
}

/* Once a frame: pt2's callback (its replayer's clock too) for the real time the frame took. */
void kestrel_audio_frame(Uint32 us)
{
    if (spec.callback) kestrel_audio_pump(us, AUDIO_RATE, AUDIO_LEAD_MS, mix, NULL);
}
void SDL_LockAudioDevice(SDL_AudioDeviceID d) { (void)d; }
void SDL_UnlockAudioDevice(SDL_AudioDeviceID d) { (void)d; }
int SDL_GetNumAudioDevices(int c) { (void)c; return 1; }
const char *SDL_GetAudioDeviceName(int i, int c) { (void)i; (void)c; return "KESTREL"; }
int SDL_GetNumAudioDrivers(void) { return 1; }
const char *SDL_GetAudioDriver(int i) { (void)i; return "kestrel"; }
SDL_bool SDL_HasSSE(void) { return SDL_FALSE; }
SDL_bool SDL_HasSSE2(void) { return SDL_FALSE; }
int SDL_setenv(const char *n, const char *v, int o) { (void)n; (void)v; (void)o; return 0; }
