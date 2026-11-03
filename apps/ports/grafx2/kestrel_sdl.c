/* The SDL2 calls GrafX2 makes, on the ZigMachine.
 *
 * Video: GrafX2 draws into one 8-bit SDL_Surface (sdlscreen.c Screen_SDL). Here that surface's pixels ARE
 * plane 0's VRAM and its palette writes go straight to palette 0, so there is nothing to present: the
 * ARGB conversion + texture upload in sdlscreen.c become no-ops (SDL_LockTexture hands back a scratch
 * line). 320x200 runs in the normal mode; anything up to 400x280 in the fullscreen (overscan) mode.
 *
 * Time and sleeping: SDL_Delay() is where GrafX2's loops wait for input; it yields the frame
 * (kestrel_yield, kestrel_main.c), so the cart returns to the machine every VBL. */
#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>

__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);
__attribute__((import_module("env"), import_name("hwVideoBase"))) extern int hwVideoBase(void);
void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }
void kestrel_yield(void);

static char window_handle, renderer_handle, texture_handle, cursor_handle;

/* --- core --- */
int SDL_Init(Uint32 flags) { (void)flags; return 0; }
const char *SDL_GetError(void) { return "KESTREL: not supported"; }
void SDL_GetVersion(SDL_version *v) { SDL_VERSION(v); }
const char *SDL_GetRevision(void) { return "kestrel"; }
SDL_bool SDL_SetHint(const char *n, const char *v) { (void)n; (void)v; return SDL_TRUE; }
int SDL_ShowSimpleMessageBox(Uint32 f, const char *t, const char *m, SDL_Window *w) { (void)f; (void)w; kestrel_log(t); kestrel_log(m); return 0; }
int SDL_setenv(const char *n, const char *v, int o) { (void)n; (void)v; (void)o; return 0; }
SDL_bool SDL_HasClipboardText(void) { return SDL_FALSE; }
char *SDL_GetClipboardText(void) { char *s = malloc(1); if (s) s[0] = 0; return s; }
void SDL_LogSetPriority(int c, SDL_LogPriority p) { (void)c; (void)p; }
void SDL_LogMessageV(int c, SDL_LogPriority p, const char *fmt, va_list ap)
{
    (void)c; (void)p;
    char b[256];
    vsnprintf(b, sizeof b, fmt, ap);
    kestrel_log(b);
}

/* --- time: one VBL = 1/60 s, advanced by kestrel_sdl_vbl() --- */
static Uint64 micros;
void kestrel_sdl_vbl(void) { micros += 1000000 / 60; }
Uint64 SDL_GetPerformanceCounter(void) { return micros; }
Uint64 SDL_GetPerformanceFrequency(void) { return 1000000; }
Uint32 SDL_GetTicks(void) { return (Uint32)(micros / 1000); }
void SDL_Delay(Uint32 ms) { (void)ms; kestrel_yield(); }

/* --- threads: none --- */
static char thread_handle;
SDL_Thread *SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data) { (void)name; fn(data); return (SDL_Thread *)&thread_handle; }
void SDL_DetachThread(SDL_Thread *t) { (void)t; }
int SDL_SetThreadPriority(SDL_ThreadPriority p) { (void)p; return 0; }

/* --- the plane --- */
#define REG_BACKGROUND 0x04
#define REG_FB_STRIDE 0x34
#define REG_FB_BASE 0x44
#define REG_FB_MODE 0x54
#define OFF_PAL 0x0100
#define OFF_VRAM 0x1100
#define FB_MODE_NORMAL 0
#define FB_MODE_FULLSCREEN 1
static Uint8 *vbase;
static int plane_w = 320, plane_h = 200;

void kestrel_video_init(void)
{
    vbase = (Uint8 *)(uintptr_t)hwVideoBase();
    *(Uint32 *)(vbase + REG_BACKGROUND) = 0xFF000000u;
}
static void plane_setup(int w, int h)
{
    int full = w > 320 || h > 200;
    plane_w = full ? 400 : 320;
    plane_h = full ? 280 : 200;
    vbase[REG_FB_MODE] = full ? FB_MODE_FULLSCREEN : FB_MODE_NORMAL;
    *(Uint16 *)(vbase + REG_FB_STRIDE) = (Uint16)plane_w;
    *(Uint32 *)(vbase + REG_FB_BASE) = OFF_VRAM;
    memset(vbase + OFF_VRAM, 0, (size_t)plane_w * (size_t)plane_h);
}
/* The host may reset the plane registers (a cart swap, the boot ROM): re-assert them each frame. */
void kestrel_video_frame(void)
{
    if (!vbase) return;
    vbase[REG_FB_MODE] = plane_w > 320 ? FB_MODE_FULLSCREEN : FB_MODE_NORMAL;
    *(Uint16 *)(vbase + REG_FB_STRIDE) = (Uint16)plane_w;
    *(Uint32 *)(vbase + REG_FB_BASE) = OFF_VRAM;
}
__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }

/* --- window / display: one fixed 320x200 "desktop" --- */
SDL_Window *SDL_CreateWindow(const char *t, int x, int y, int w, int h, Uint32 f) { (void)t; (void)x; (void)y; (void)f; plane_setup(w, h); return (SDL_Window *)&window_handle; }
void SDL_DestroyWindow(SDL_Window *w) { (void)w; }
Uint32 SDL_GetWindowFlags(SDL_Window *w) { (void)w; return SDL_WINDOW_INPUT_FOCUS; }
void SDL_GetWindowSize(SDL_Window *w, int *ww, int *hh) { (void)w; if (ww) *ww = plane_w; if (hh) *hh = plane_h; }
void SDL_SetWindowSize(SDL_Window *w, int ww, int hh) { (void)w; plane_setup(ww, hh); }
void SDL_GL_GetDrawableSize(SDL_Window *w, int *ww, int *hh) { SDL_GetWindowSize(w, ww, hh); }
void SDL_GetWindowPosition(SDL_Window *w, int *x, int *y) { (void)w; if (x) *x = 0; if (y) *y = 0; }
int SDL_GetWindowDisplayIndex(SDL_Window *w) { (void)w; return 0; }
int SDL_GetWindowBordersSize(SDL_Window *w, int *t, int *l, int *b, int *r) { (void)w; if (t) *t = 0; if (l) *l = 0; if (b) *b = 0; if (r) *r = 0; return 0; }
SDL_Window *SDL_GetWindowFromID(Uint32 id) { (void)id; return (SDL_Window *)&window_handle; }
static void mode(SDL_DisplayMode *dm, int w, int h) { dm->format = SDL_PIXELFORMAT_INDEX8; dm->w = w; dm->h = h; dm->refresh_rate = 60; dm->driverdata = NULL; }
int SDL_GetDesktopDisplayMode(int i, SDL_DisplayMode *dm) { (void)i; mode(dm, 320, 200); return 0; }
int SDL_GetNumDisplayModes(int d) { (void)d; return 2; }
int SDL_GetDisplayMode(int d, int m, SDL_DisplayMode *dm) { (void)d; if (m == 0) mode(dm, 320, 200); else mode(dm, 400, 280); return 0; }
const char *SDL_GetCurrentVideoDriver(void) { return "kestrel"; }
void SDL_SetWindowTitle(SDL_Window *w, const char *t) { (void)w; (void)t; }
void SDL_SetWindowIcon(SDL_Window *w, SDL_Surface *i) { (void)w; (void)i; }
int SDL_SetWindowFullscreen(SDL_Window *w, Uint32 f) { (void)w; (void)f; return 0; }
void SDL_ShowWindow(SDL_Window *w) { (void)w; }
void SDL_RaiseWindow(SDL_Window *w) { (void)w; }
void SDL_RestoreWindow(SDL_Window *w) { (void)w; }
void SDL_EnableScreenSaver(void) {}
SDL_bool SDL_GetWindowWMInfo(SDL_Window *w, SDL_SysWMinfo *i) { (void)w; (void)i; return SDL_FALSE; }
SDL_Surface *SDL_GetWindowSurface(SDL_Window *w) { (void)w; return NULL; }
int SDL_UpdateWindowSurface(SDL_Window *w) { (void)w; return 0; }
int SDL_UpdateWindowSurfaceRects(SDL_Window *w, const SDL_Rect *r, int n) { (void)w; (void)r; (void)n; return 0; }

/* --- renderer / texture: nothing to present (the surface is the plane) --- */
static Uint32 scratch_line[400];
SDL_Renderer *SDL_CreateRenderer(SDL_Window *w, int i, Uint32 f) { (void)w; (void)i; (void)f; return (SDL_Renderer *)&renderer_handle; }
void SDL_DestroyRenderer(SDL_Renderer *r) { (void)r; }
int SDL_SetRenderDrawColor(SDL_Renderer *r, Uint8 a, Uint8 b, Uint8 c, Uint8 d) { (void)r; (void)a; (void)b; (void)c; (void)d; return 0; }
int SDL_SetRenderDrawBlendMode(SDL_Renderer *r, SDL_BlendMode m) { (void)r; (void)m; return 0; }
int SDL_RenderClear(SDL_Renderer *r) { (void)r; return 0; }
int SDL_RenderCopy(SDL_Renderer *r, SDL_Texture *t, const SDL_Rect *s, const SDL_Rect *d) { (void)r; (void)t; (void)s; (void)d; return 0; }
void SDL_RenderPresent(SDL_Renderer *r) { (void)r; }
SDL_Texture *SDL_CreateTexture(SDL_Renderer *r, Uint32 f, int a, int w, int h) { (void)r; (void)f; (void)a; (void)w; (void)h; return (SDL_Texture *)&texture_handle; }
void SDL_DestroyTexture(SDL_Texture *t) { (void)t; }
int SDL_SetTextureBlendMode(SDL_Texture *t, SDL_BlendMode m) { (void)t; (void)m; return 0; }
int SDL_SetTextureScaleMode(SDL_Texture *t, SDL_ScaleMode m) { (void)t; (void)m; return 0; }
int SDL_UpdateTexture(SDL_Texture *t, const SDL_Rect *r, const void *px, int pitch) { (void)t; (void)r; (void)px; (void)pitch; return 0; }
/* sdlscreen.c copies its ARGB rows into the texture: hand it one scratch row with pitch 0. */
int SDL_LockTexture(SDL_Texture *t, const SDL_Rect *r, void **px, int *pitch) { (void)t; (void)r; *px = scratch_line; *pitch = 0; return 0; }
void SDL_UnlockTexture(SDL_Texture *t) { (void)t; }

/* --- surfaces: an 8-bit surface the size of the window is the plane; others live in the heap --- */
static SDL_Color pal_colors[256];
static SDL_Palette hw_palette = { 256, pal_colors, 0, 1 };
static SDL_PixelFormat fmt8 = { SDL_PIXELFORMAT_INDEX8, &hw_palette, 8, 1, { 0, 0 }, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
static SDL_PixelFormat fmt32 = { SDL_PIXELFORMAT_ARGB8888, NULL, 32, 4, { 0, 0 }, 0xFF0000, 0xFF00, 0xFF, 0xFF000000u, 0, 0, 0, 0, 16, 8, 0, 24 };

SDL_Surface *SDL_CreateRGBSurface(Uint32 f, int w, int h, int depth, Uint32 rm, Uint32 gm, Uint32 bm, Uint32 am)
{
    (void)f; (void)rm; (void)gm; (void)bm; (void)am;
    SDL_Surface *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->w = w; s->h = h; s->clip_rect = (SDL_Rect){ 0, 0, w, h };
    if (depth == 8 && vbase && w <= plane_w && h <= plane_h && w >= 320) {
        s->format = &fmt8; s->pitch = plane_w;
        s->pixels = vbase + OFF_VRAM;          /* the screen: drawn straight into plane 0 */
        s->userdata = (void *)1;                /* not ours to free */
        return s;
    }
    s->format = depth == 8 ? &fmt8 : &fmt32;
    s->pitch = w * (depth == 8 ? 1 : 4);
    s->pixels = calloc((size_t)s->pitch * (size_t)h, 1);
    if (!s->pixels) { free(s); return NULL; }
    return s;
}
void SDL_FreeSurface(SDL_Surface *s) { if (!s) return; if (!s->userdata) free(s->pixels); free(s); }
int SDL_LockSurface(SDL_Surface *s) { (void)s; return 0; }
void SDL_UnlockSurface(SDL_Surface *s) { (void)s; }
int SDL_SetColorKey(SDL_Surface *s, int f, Uint32 k) { (void)s; (void)f; (void)k; return 0; }
int SDL_SetSurfaceRLE(SDL_Surface *s, int f) { (void)s; (void)f; return 0; }
int SDL_SetSurfaceBlendMode(SDL_Surface *s, SDL_BlendMode m) { (void)s; (void)m; return 0; }
Uint32 SDL_MapRGB(const SDL_PixelFormat *f, Uint8 r, Uint8 g, Uint8 b) { (void)f; return 0xFF000000u | (Uint32)r << 16 | (Uint32)g << 8 | b; }
int SDL_FillRect(SDL_Surface *s, const SDL_Rect *r, Uint32 c)
{
    SDL_Rect a = r ? *r : (SDL_Rect){ 0, 0, s->w, s->h };
    for (int y = a.y; y < a.y + a.h && y < s->h; y++)
        for (int x = a.x; x < a.x + a.w && x < s->w; x++) {
            if (x < 0 || y < 0) continue;
            if (s->format->BytesPerPixel == 1) ((Uint8 *)s->pixels)[y * s->pitch + x] = (Uint8)c;
            else ((Uint32 *)s->pixels)[y * (s->pitch / 4) + x] = c;
        }
    return 0;
}
/* Only sdlscreen.c's 8 -> 32 conversion blits; on KESTREL there is nothing to convert. */
int SDL_BlitSurface(SDL_Surface *src, const SDL_Rect *sr, SDL_Surface *dst, SDL_Rect *dr) { (void)src; (void)sr; (void)dst; (void)dr; return 0; }

/* Palette writes on the screen surface go to the hardware palette 0 (RGBA, alpha 255). */
int SDL_SetPaletteColors(SDL_Palette *p, const SDL_Color *c, int first, int n)
{
    for (int i = 0; i < n && first + i < 256; i++) {
        p->colors[first + i] = c[i];
        if (p == &hw_palette && vbase) {
            Uint8 *e = vbase + OFF_PAL + (first + i) * 4;
            e[0] = c[i].r; e[1] = c[i].g; e[2] = c[i].b; e[3] = 255;
        }
    }
    return 0;
}

/* --- mouse cursor: GrafX2 draws its own --- */
int SDL_ShowCursor(int t) { (void)t; return 0; }
SDL_Cursor *SDL_CreateColorCursor(SDL_Surface *s, int x, int y) { (void)s; (void)x; (void)y; return (SDL_Cursor *)&cursor_handle; }
SDL_Cursor *SDL_CreateCursor(const Uint8 *d, const Uint8 *m, int w, int h, int x, int y) { (void)d; (void)m; (void)w; (void)h; (void)x; (void)y; return (SDL_Cursor *)&cursor_handle; }
SDL_Cursor *SDL_GetDefaultCursor(void) { return (SDL_Cursor *)&cursor_handle; }
void SDL_SetCursor(SDL_Cursor *c) { (void)c; }
void SDL_FreeCursor(SDL_Cursor *c) { (void)c; }
int SDL_CaptureMouse(SDL_bool e) { (void)e; return 0; }
void SDL_WarpMouseInWindow(SDL_Window *w, int x, int y) { (void)w; (void)x; (void)y; }

/* --- events not from the input exports --- */
Uint8 SDL_EventState(Uint32 t, int s) { (void)t; (void)s; return SDL_ENABLE; }
void SDL_PumpEvents(void) {}

/* --- audio: GrafX2 has none --- */
SDL_AudioDeviceID SDL_OpenAudioDevice(const char *d, int c, const SDL_AudioSpec *w, SDL_AudioSpec *h, int a) { (void)d; (void)c; (void)w; (void)h; (void)a; return 0; }
void SDL_CloseAudioDevice(SDL_AudioDeviceID d) { (void)d; }
void SDL_PauseAudioDevice(SDL_AudioDeviceID d, int p) { (void)d; (void)p; }
SDL_bool SDL_HasSSE(void) { return SDL_FALSE; }
SDL_bool SDL_HasSSE2(void) { return SDL_FALSE; }
