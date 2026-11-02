/* SDL2 shim for KESTREL C ports (pt2-clone, GrafX2, klystrack): the subset they use, laid out like SDL2.
 * Types, constants and declarations only; the implementations are apps/ports/kestrel_sdl2/src (input,
 * heap, WASI) and each port's kestrel_sdl.c (video present, audio). Values follow real SDL2 where a
 * program can see them (scancodes = USB HID usage ids, keycodes, event and flag numbers). */
#ifndef KESTREL_SDL_SHIM_H
#define KESTREL_SDL_SHIM_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <ctype.h>
#include <stdarg.h>
#include <wchar.h>  /* real SDL_stdinc.h pulls these in; pt2 relies on it */
#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t Uint8;   typedef int8_t Sint8;
typedef uint16_t Uint16; typedef int16_t Sint16;
typedef uint32_t Uint32; typedef int32_t Sint32;
typedef uint64_t Uint64; typedef int64_t Sint64;
typedef enum { SDL_FALSE = 0, SDL_TRUE = 1 } SDL_bool;

#define SDL_MAJOR_VERSION 2
#define SDL_MINOR_VERSION 30
#define SDL_PATCHLEVEL 0
typedef struct SDL_version { Uint8 major, minor, patch; } SDL_version;
#define SDL_VERSION(x) do { (x)->major = SDL_MAJOR_VERSION; (x)->minor = SDL_MINOR_VERSION; (x)->patch = SDL_PATCHLEVEL; } while (0)
void SDL_GetVersion(SDL_version *ver);

#define SDL_INIT_AUDIO 0x10u
#define SDL_INIT_VIDEO 0x20u
#define SDL_INIT_JOYSTICK 0x200u
int SDL_Init(Uint32 flags);
void SDL_Quit(void);
const char *SDL_GetError(void);
void SDL_Delay(Uint32 ms);
Uint64 SDL_GetPerformanceCounter(void);
Uint64 SDL_GetPerformanceFrequency(void);
SDL_bool SDL_HasSSE(void);
SDL_bool SDL_HasSSE2(void);
#define SDL_free free
int SDL_setenv(const char *name, const char *value, int overwrite);

/* hints */
#define SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR "SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR"
#define SDL_RENDER_SCALE_QUALITY "SDL_RENDER_SCALE_QUALITY"
#define SDL_MOUSE_FOCUS_CLICKTHROUGH "SDL_MOUSE_FOCUS_CLICKTHROUGH"
#define SDL_WINDOWS_NO_CLOSE_ON_ALT_F4 "SDL_WINDOWS_NO_CLOSE_ON_ALT_F4"
#define SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR "SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR"
#define SDL_AUDIODRIVER "SDL_AUDIODRIVER"
SDL_bool SDL_SetHint(const char *name, const char *value);

/* threads: none on the cart; mod2wav / pat2smp run inline or are disabled */
typedef struct SDL_Thread SDL_Thread;
typedef int (*SDL_ThreadFunction)(void *data);
typedef enum { SDL_THREAD_PRIORITY_LOW, SDL_THREAD_PRIORITY_NORMAL, SDL_THREAD_PRIORITY_HIGH } SDL_ThreadPriority;
SDL_Thread *SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data);
void SDL_DetachThread(SDL_Thread *t);
int SDL_SetThreadPriority(SDL_ThreadPriority p);

/* video */
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
typedef struct SDL_Rect { int x, y, w, h; } SDL_Rect;
typedef struct SDL_DisplayMode { Uint32 format; int w, h, refresh_rate; void *driverdata; } SDL_DisplayMode;
typedef struct SDL_Color { Uint8 r, g, b, a; } SDL_Color;
typedef struct SDL_Palette { int ncolors; SDL_Color *colors; Uint32 version; int refcount; } SDL_Palette;
typedef struct SDL_PixelFormat {
    Uint32 format; SDL_Palette *palette; Uint8 BitsPerPixel, BytesPerPixel, padding[2];
    Uint32 Rmask, Gmask, Bmask, Amask; Uint8 Rloss, Gloss, Bloss, Aloss, Rshift, Gshift, Bshift, Ashift;
} SDL_PixelFormat;
typedef struct SDL_Surface { Uint32 flags; SDL_PixelFormat *format; int w, h, pitch; void *pixels; void *userdata; int locked; SDL_Rect clip_rect; } SDL_Surface;
#define SDL_PIXELFORMAT_INDEX8 0x13000801u
#define SDL_MUSTLOCK(s) 0
int SDL_SetPaletteColors(SDL_Palette *p, const SDL_Color *colors, int first, int n);
int SDL_FillRect(SDL_Surface *s, const SDL_Rect *r, Uint32 color);
int SDL_BlitSurface(SDL_Surface *src, const SDL_Rect *sr, SDL_Surface *dst, SDL_Rect *dr);
SDL_Surface *SDL_GetWindowSurface(SDL_Window *w);
int SDL_UpdateWindowSurface(SDL_Window *w);
int SDL_UpdateWindowSurfaceRects(SDL_Window *w, const SDL_Rect *r, int n);
int SDL_LockTexture(SDL_Texture *t, const SDL_Rect *r, void **pixels, int *pitch);
void SDL_UnlockTexture(SDL_Texture *t);
typedef enum { SDL_ScaleModeNearest, SDL_ScaleModeLinear, SDL_ScaleModeBest } SDL_ScaleMode;
int SDL_SetTextureScaleMode(SDL_Texture *t, SDL_ScaleMode m);
void SDL_SetWindowSize(SDL_Window *w, int ww, int hh);
void SDL_SetWindowIcon(SDL_Window *w, SDL_Surface *icon);
int SDL_GetNumDisplayModes(int display);
int SDL_GetDisplayMode(int display, int mode, SDL_DisplayMode *dm);
const char *SDL_GetCurrentVideoDriver(void);
SDL_Window *SDL_GetWindowFromID(Uint32 id);
int SDL_GetWindowBordersSize(SDL_Window *w, int *top, int *left, int *bottom, int *right);
#define SDL_WINDOWPOS_UNDEFINED 0x1FFF0000
#define SDL_WINDOW_FULLSCREEN 0x1u
#define SDL_WINDOW_RESIZABLE 0x20u
#define SDL_RENDERER_ACCELERATED 0x2u
Uint32 SDL_GetTicks(void);
#define SDL_TICKS_PASSED(A, B) ((Sint32)((B) - (A)) <= 0)
#define SDL_VERSION_ATLEAST(X, Y, Z) ((SDL_MAJOR_VERSION * 1000 + SDL_MINOR_VERSION * 100 + SDL_PATCHLEVEL) >= ((X) * 1000 + (Y) * 100 + (Z)))
const char *SDL_GetRevision(void);
SDL_bool SDL_HasClipboardText(void);
char *SDL_GetClipboardText(void);
/* logging */
typedef enum { SDL_LOG_PRIORITY_VERBOSE = 1, SDL_LOG_PRIORITY_DEBUG, SDL_LOG_PRIORITY_INFO, SDL_LOG_PRIORITY_WARN, SDL_LOG_PRIORITY_ERROR, SDL_LOG_PRIORITY_CRITICAL } SDL_LogPriority;
#define SDL_LOG_CATEGORY_APPLICATION 0
void SDL_LogSetPriority(int category, SDL_LogPriority p);
void SDL_LogMessageV(int category, SDL_LogPriority p, const char *fmt, va_list ap);
typedef enum { SDL_BLENDMODE_NONE = 0, SDL_BLENDMODE_BLEND = 1 } SDL_BlendMode;
#define SDL_ALPHA_OPAQUE 255
#define SDL_PIXELFORMAT_ARGB8888 0x16362004u
#define SDL_TEXTUREACCESS_STREAMING 1
#define SDL_RENDERER_PRESENTVSYNC 0x4u
#define SDL_WINDOWPOS_CENTERED 0x2FFF0000
#define SDL_WINDOW_FULLSCREEN_DESKTOP 0x1001u
#define SDL_WINDOW_HIDDEN 0x8u
#define SDL_WINDOW_MINIMIZED 0x40u
#define SDL_WINDOW_INPUT_FOCUS 0x200u
#define SDL_WINDOW_ALLOW_HIGHDPI 0x2000u
SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, Uint32 flags);
void SDL_DestroyWindow(SDL_Window *w);
Uint32 SDL_GetWindowFlags(SDL_Window *w);
void SDL_GetWindowSize(SDL_Window *w, int *ww, int *hh);
void SDL_GetWindowPosition(SDL_Window *w, int *x, int *y);
int SDL_GetWindowDisplayIndex(SDL_Window *w);
int SDL_GetDesktopDisplayMode(int idx, SDL_DisplayMode *dm);
void SDL_SetWindowTitle(SDL_Window *w, const char *t);
int SDL_SetWindowFullscreen(SDL_Window *w, Uint32 flags);
void SDL_ShowWindow(SDL_Window *w);
void SDL_RaiseWindow(SDL_Window *w);
void SDL_RestoreWindow(SDL_Window *w);
void SDL_EnableScreenSaver(void);
void SDL_GL_GetDrawableSize(SDL_Window *w, int *ww, int *hh);
SDL_Renderer *SDL_CreateRenderer(SDL_Window *w, int index, Uint32 flags);
void SDL_DestroyRenderer(SDL_Renderer *r);
int SDL_SetRenderDrawColor(SDL_Renderer *r, Uint8 cr, Uint8 cg, Uint8 cb, Uint8 ca);
int SDL_SetRenderDrawBlendMode(SDL_Renderer *r, SDL_BlendMode m);
int SDL_RenderClear(SDL_Renderer *r);
int SDL_RenderCopy(SDL_Renderer *r, SDL_Texture *t, const SDL_Rect *src, const SDL_Rect *dst);
void SDL_RenderPresent(SDL_Renderer *r);
SDL_Texture *SDL_CreateTexture(SDL_Renderer *r, Uint32 format, int access, int w, int h);
void SDL_DestroyTexture(SDL_Texture *t);
int SDL_SetTextureBlendMode(SDL_Texture *t, SDL_BlendMode m);
int SDL_UpdateTexture(SDL_Texture *t, const SDL_Rect *rect, const void *pixels, int pitch);
SDL_Surface *SDL_CreateRGBSurface(Uint32 flags, int w, int h, int depth, Uint32 rm, Uint32 gm, Uint32 bm, Uint32 am);
void SDL_FreeSurface(SDL_Surface *s);
int SDL_LockSurface(SDL_Surface *s);
void SDL_UnlockSurface(SDL_Surface *s);
int SDL_SetColorKey(SDL_Surface *s, int flag, Uint32 key);
int SDL_SetSurfaceRLE(SDL_Surface *s, int flag);
int SDL_SetSurfaceBlendMode(SDL_Surface *s, SDL_BlendMode m);
Uint32 SDL_MapRGB(const SDL_PixelFormat *f, Uint8 r, Uint8 g, Uint8 b);
#define SDL_MESSAGEBOX_ERROR 0x10u
#define SDL_MESSAGEBOX_WARNING 0x20u
#define SDL_MESSAGEBOX_INFORMATION 0x40u
int SDL_ShowSimpleMessageBox(Uint32 flags, const char *title, const char *msg, SDL_Window *w);

/* mouse */
typedef struct SDL_Cursor SDL_Cursor;
#define SDL_BUTTON_LEFT 1
#define SDL_BUTTON_MIDDLE 2
#define SDL_BUTTON_RIGHT 3
#define SDL_BUTTON(x) (1u << ((x) - 1))
#define SDL_BUTTON_LMASK SDL_BUTTON(SDL_BUTTON_LEFT)
#define SDL_BUTTON_RMASK SDL_BUTTON(SDL_BUTTON_RIGHT)
Uint32 SDL_GetMouseState(int *x, int *y);
Uint32 SDL_GetGlobalMouseState(int *x, int *y);
void SDL_WarpMouseInWindow(SDL_Window *w, int x, int y);
int SDL_ShowCursor(int toggle);
SDL_Cursor *SDL_CreateColorCursor(SDL_Surface *s, int hx, int hy);
SDL_Cursor *SDL_GetDefaultCursor(void);
void SDL_SetCursor(SDL_Cursor *c);
void SDL_FreeCursor(SDL_Cursor *c);
SDL_Cursor *SDL_CreateCursor(const Uint8 *data, const Uint8 *mask, int w, int h, int hx, int hy);
int SDL_CaptureMouse(SDL_bool enabled);
#define SDL_BUTTON_X1 4
#define SDL_BUTTON_X2 5

/* keyboard */
typedef enum {
#include "scancodes.inc"
    SDL_NUM_SCANCODES = 512
} SDL_Scancode;
typedef Sint32 SDL_Keycode;
#define SDLK_SCANCODE_MASK (1 << 30)
#include "keycodes.inc"
typedef enum {
    KMOD_NONE = 0, KMOD_LSHIFT = 0x1, KMOD_RSHIFT = 0x2, KMOD_LCTRL = 0x40, KMOD_RCTRL = 0x80,
    KMOD_LALT = 0x100, KMOD_RALT = 0x200, KMOD_LGUI = 0x400, KMOD_RGUI = 0x800, KMOD_NUM = 0x1000, KMOD_CAPS = 0x2000,
    KMOD_MODE = 0x4000, KMOD_CTRL = 0xC0, KMOD_SHIFT = 0x3, KMOD_ALT = 0x300, KMOD_GUI = 0xC00
} SDL_Keymod;
SDL_Keymod SDL_GetModState(void);
void SDL_SetModState(SDL_Keymod m);
void SDL_StartTextInput(void);
void SDL_StopTextInput(void);

/* game controllers: the button numbers only (no controller API on the cart yet) */
typedef enum {
    SDL_CONTROLLER_BUTTON_INVALID = -1, SDL_CONTROLLER_BUTTON_A, SDL_CONTROLLER_BUTTON_B, SDL_CONTROLLER_BUTTON_X,
    SDL_CONTROLLER_BUTTON_Y, SDL_CONTROLLER_BUTTON_BACK, SDL_CONTROLLER_BUTTON_GUIDE, SDL_CONTROLLER_BUTTON_START,
    SDL_CONTROLLER_BUTTON_LEFTSTICK, SDL_CONTROLLER_BUTTON_RIGHTSTICK, SDL_CONTROLLER_BUTTON_LEFTSHOULDER,
    SDL_CONTROLLER_BUTTON_RIGHTSHOULDER, SDL_CONTROLLER_BUTTON_DPAD_UP, SDL_CONTROLLER_BUTTON_DPAD_DOWN,
    SDL_CONTROLLER_BUTTON_DPAD_LEFT, SDL_CONTROLLER_BUTTON_DPAD_RIGHT
} SDL_GameControllerButton;
const char *SDL_GetKeyName(SDL_Keycode key);

/* events */
enum {
    SDL_QUIT = 0x100, SDL_WINDOWEVENT = 0x200, SDL_SYSWMEVENT = 0x201,
    SDL_KEYDOWN = 0x300, SDL_KEYUP = 0x301, SDL_TEXTINPUT = 0x303,
    SDL_MOUSEMOTION = 0x400, SDL_MOUSEBUTTONDOWN = 0x401, SDL_MOUSEBUTTONUP = 0x402, SDL_MOUSEWHEEL = 0x403,
    SDL_TEXTEDITING = 0x302, SDL_JOYAXISMOTION = 0x600, SDL_JOYBUTTONDOWN = 0x603, SDL_JOYBUTTONUP = 0x604,
    SDL_FINGERDOWN = 0x700, SDL_FINGERUP = 0x701, SDL_FINGERMOTION = 0x702,
    SDL_DROPFILE = 0x1000, SDL_DROPTEXT = 0x1001, SDL_DROPBEGIN = 0x1002, SDL_DROPCOMPLETE = 0x1003,
    SDL_USEREVENT = 0x8000, SDL_FIRSTEVENT = 0, SDL_LASTEVENT = 0xFFFF
};
enum {
    SDL_WINDOWEVENT_SHOWN = 1, SDL_WINDOWEVENT_HIDDEN = 2, SDL_WINDOWEVENT_EXPOSED = 3, SDL_WINDOWEVENT_MOVED = 4,
    SDL_WINDOWEVENT_RESIZED = 5, SDL_WINDOWEVENT_SIZE_CHANGED = 6, SDL_WINDOWEVENT_MINIMIZED = 7,
    SDL_WINDOWEVENT_MAXIMIZED = 8, SDL_WINDOWEVENT_RESTORED = 9, SDL_WINDOWEVENT_ENTER = 10, SDL_WINDOWEVENT_LEAVE = 11,
    SDL_WINDOWEVENT_FOCUS_GAINED = 12, SDL_WINDOWEVENT_FOCUS_LOST = 13, SDL_WINDOWEVENT_CLOSE = 14
};
#define SDL_DISABLE 0
#define SDL_ENABLE 1
typedef struct SDL_Keysym { SDL_Scancode scancode; SDL_Keycode sym; Uint16 mod; Uint32 unused; } SDL_Keysym;
typedef struct SDL_SysWMmsg SDL_SysWMmsg;
typedef struct SDL_CommonEvent { Uint32 type, timestamp; } SDL_CommonEvent;
typedef struct SDL_QuitEvent { Uint32 type, timestamp; } SDL_QuitEvent;
typedef struct SDL_WindowEvent { Uint32 type, timestamp, windowID; Uint8 event, padding1, padding2, padding3; Sint32 data1, data2; } SDL_WindowEvent;
typedef struct SDL_KeyboardEvent { Uint32 type, timestamp, windowID; Uint8 state, repeat, padding2, padding3; SDL_Keysym keysym; } SDL_KeyboardEvent;
typedef struct SDL_TextInputEvent { Uint32 type, timestamp, windowID; char text[32]; } SDL_TextInputEvent;
typedef struct SDL_TextEditingEvent { Uint32 type, timestamp, windowID; char text[32]; Sint32 start, length; } SDL_TextEditingEvent;
typedef struct SDL_MouseMotionEvent { Uint32 type, timestamp, windowID, which, state; Sint32 x, y, xrel, yrel; } SDL_MouseMotionEvent;
typedef struct SDL_MouseButtonEvent { Uint32 type, timestamp, windowID, which; Uint8 button, state, clicks, padding1; Sint32 x, y; } SDL_MouseButtonEvent;
typedef struct SDL_MouseWheelEvent { Uint32 type, timestamp, windowID, which; Sint32 x, y; Uint32 direction; } SDL_MouseWheelEvent;
typedef struct SDL_JoyAxisEvent { Uint32 type, timestamp; Sint32 which; Uint8 axis, padding1, padding2, padding3; Sint16 value; } SDL_JoyAxisEvent;
typedef struct SDL_JoyButtonEvent { Uint32 type, timestamp; Sint32 which; Uint8 button, state; } SDL_JoyButtonEvent;
typedef struct SDL_TouchFingerEvent { Uint32 type, timestamp; Sint64 touchId, fingerId; float x, y, dx, dy, pressure; Uint32 windowID; } SDL_TouchFingerEvent;
typedef struct SDL_DropEvent { Uint32 type, timestamp; char *file; Uint32 windowID; } SDL_DropEvent;
typedef struct SDL_SysWMEvent { Uint32 type, timestamp; SDL_SysWMmsg *msg; } SDL_SysWMEvent;
typedef struct SDL_UserEvent { Uint32 type, timestamp, windowID; Sint32 code; void *data1, *data2; } SDL_UserEvent;
typedef union SDL_Event {
    Uint32 type;
    SDL_CommonEvent common; SDL_QuitEvent quit; SDL_WindowEvent window; SDL_KeyboardEvent key;
    SDL_TextInputEvent text; SDL_TextEditingEvent edit; SDL_MouseMotionEvent motion; SDL_MouseButtonEvent button;
    SDL_MouseWheelEvent wheel; SDL_JoyAxisEvent jaxis; SDL_JoyButtonEvent jbutton; SDL_TouchFingerEvent tfinger;
    SDL_DropEvent drop; SDL_SysWMEvent syswm; SDL_UserEvent user;
    Uint8 padding[56];
} SDL_Event;
typedef enum { SDL_ADDEVENT, SDL_PEEKEVENT, SDL_GETEVENT } SDL_eventaction;
int SDL_PeepEvents(SDL_Event *e, int n, SDL_eventaction a, Uint32 minType, Uint32 maxType);
void SDL_PumpEvents(void);
int SDL_PollEvent(SDL_Event *e);
int SDL_PushEvent(SDL_Event *e);
Uint8 SDL_EventState(Uint32 type, int state);

/* audio: pt2 mixes in its callback; the shim calls it from frame() and feeds the cart's PCM stream */
typedef Uint32 SDL_AudioDeviceID;
typedef Uint16 SDL_AudioFormat;
typedef void (*SDL_AudioCallback)(void *userdata, Uint8 *stream, int len);
typedef struct SDL_AudioSpec {
    int freq; SDL_AudioFormat format; Uint8 channels, silence; Uint16 samples, padding; Uint32 size;
    SDL_AudioCallback callback; void *userdata;
} SDL_AudioSpec;
#define AUDIO_S16 0x8010
#define SDL_AUDIO_ALLOW_FREQUENCY_CHANGE 0x1
SDL_AudioDeviceID SDL_OpenAudioDevice(const char *dev, int iscapture, const SDL_AudioSpec *want, SDL_AudioSpec *have, int allowed);
void SDL_CloseAudioDevice(SDL_AudioDeviceID d);
void SDL_PauseAudioDevice(SDL_AudioDeviceID d, int pause_on);
void SDL_LockAudioDevice(SDL_AudioDeviceID d);
void SDL_UnlockAudioDevice(SDL_AudioDeviceID d);
int SDL_GetNumAudioDevices(int iscapture);
const char *SDL_GetAudioDeviceName(int index, int iscapture);
int SDL_GetNumAudioDrivers(void);
const char *SDL_GetAudioDriver(int index);

/* --- added for klystrack (2026-11-01); implemented by the src/opt modules, which a port links only if its Makefile lists
 * them (pt2 and GrafX2 define their own SDL_Renderer / surface stubs, so the opt modules would collide there) --- */
#define SDL_INIT_TIMER 0x1u
#define SDL_INIT_NOPARACHUTE 0x100000u
#define SDL_SWSURFACE 0
#define SDL_WINDOW_OPENGL 0x2u
#define SDL_WINDOW_MAXIMIZED 0x80u
#define SDL_RENDERER_SOFTWARE 0x1u
#define SDL_RENDERER_TARGETTEXTURE 0x8u
#define SDL_TEXTUREACCESS_STATIC 0
#define SDL_TEXTUREACCESS_TARGET 2
#define SDL_PIXELFORMAT_RGB888 0x16161804u
#define SDL_PIXELFORMAT_RGBA8888 0x16462004u
#define SDL_BLENDMODE_ADD 2
#define SDL_BLENDMODE_MOD 4
#define AUDIO_S16LSB 0x8010
#define AUDIO_S16SYS AUDIO_S16LSB
char *SDL_getenv(const char *name);
char *SDL_GetBasePath(void);
typedef struct SDL_RendererInfo {
    const char *name; Uint32 flags, num_texture_formats, texture_formats[16]; int max_texture_width, max_texture_height;
} SDL_RendererInfo;
int SDL_GetRendererInfo(SDL_Renderer *r, SDL_RendererInfo *info);
SDL_Renderer *SDL_CreateSoftwareRenderer(SDL_Surface *target);
SDL_Texture *SDL_CreateTextureFromSurface(SDL_Renderer *r, SDL_Surface *s);
int SDL_SetRenderTarget(SDL_Renderer *r, SDL_Texture *t);
int SDL_RenderSetViewport(SDL_Renderer *r, const SDL_Rect *rect);
int SDL_RenderSetScale(SDL_Renderer *r, float sx, float sy);
int SDL_RenderSetClipRect(SDL_Renderer *r, const SDL_Rect *rect);
void SDL_RenderGetClipRect(SDL_Renderer *r, SDL_Rect *rect);
int SDL_RenderFillRect(SDL_Renderer *r, const SDL_Rect *rect);
int SDL_RenderDrawLine(SDL_Renderer *r, int x1, int y1, int x2, int y2);
int SDL_SetTextureColorMod(SDL_Texture *t, Uint8 r, Uint8 g, Uint8 b);
int SDL_GetColorKey(SDL_Surface *s, Uint32 *key);
void SDL_GetRGB(Uint32 pixel, const SDL_PixelFormat *f, Uint8 *r, Uint8 *g, Uint8 *b);
SDL_Surface *SDL_ConvertSurfaceFormat(SDL_Surface *s, Uint32 format, Uint32 flags);
int SDL_BlitScaled(SDL_Surface *src, const SDL_Rect *sr, SDL_Surface *dst, SDL_Rect *dr);
void SDL_SetWindowMinimumSize(SDL_Window *w, int mw, int mh);
typedef enum { SDL_SYSTEM_CURSOR_ARROW } SDL_SystemCursor;
SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id);

/* RWops (SDL 2.30 layout; read/write return object counts) */
#define SDL_RWOPS_UNKNOWN 0u
#define SDL_RWOPS_STDFILE 2u
#define SDL_RWOPS_MEMORY 4u
#define SDL_RWOPS_MEMORY_RO 5u
#define RW_SEEK_SET 0
#define RW_SEEK_CUR 1
#define RW_SEEK_END 2
typedef struct SDL_RWops {
    Sint64 (*size)(struct SDL_RWops *context);
    Sint64 (*seek)(struct SDL_RWops *context, Sint64 offset, int whence);
    size_t (*read)(struct SDL_RWops *context, void *ptr, size_t size, size_t maxnum);
    size_t (*write)(struct SDL_RWops *context, const void *ptr, size_t size, size_t num);
    int (*close)(struct SDL_RWops *context);
    Uint32 type;
    union {
        struct { SDL_bool autoclose; FILE *fp; } stdio;
        struct { Uint8 *base, *here, *stop; } mem;
        struct { void *data1, *data2; } unknown;
    } hidden;
} SDL_RWops;
SDL_RWops *SDL_RWFromFile(const char *file, const char *mode);
SDL_RWops *SDL_RWFromFP(FILE *fp, SDL_bool autoclose);
SDL_RWops *SDL_RWFromMem(void *mem, int size);
SDL_RWops *SDL_RWFromConstMem(const void *mem, int size);
SDL_RWops *SDL_AllocRW(void);
void SDL_FreeRW(SDL_RWops *area);
Sint64 SDL_RWsize(SDL_RWops *context);
Sint64 SDL_RWseek(SDL_RWops *context, Sint64 offset, int whence);
Sint64 SDL_RWtell(SDL_RWops *context);
size_t SDL_RWread(SDL_RWops *context, void *ptr, size_t size, size_t maxnum);
size_t SDL_RWwrite(SDL_RWops *context, const void *ptr, size_t size, size_t num);
int SDL_RWclose(SDL_RWops *context);
SDL_Surface *SDL_LoadBMP_RW(SDL_RWops *src, int freesrc);

/* timers and mutexes: no threads on the cart; timers fire from the port's frame() (kestrel_timers_tick) */
typedef int SDL_TimerID;
typedef Uint32 (*SDL_TimerCallback)(Uint32 interval, void *param);
SDL_TimerID SDL_AddTimer(Uint32 interval, SDL_TimerCallback callback, void *param);
SDL_bool SDL_RemoveTimer(SDL_TimerID id);
typedef struct SDL_mutex SDL_mutex;
SDL_mutex *SDL_CreateMutex(void);
void SDL_DestroyMutex(SDL_mutex *m);
int SDL_LockMutex(SDL_mutex *m);
int SDL_UnlockMutex(SDL_mutex *m);

/* legacy audio API (device 1) */
int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained);
void SDL_PauseAudio(int pause_on);
void SDL_CloseAudio(void);
#include "SDL_endian.h"  /* the real SDL.h pulls it in too (klystrack's wavewriter.c relies on it) */

#ifdef __cplusplus
}
#endif
#endif
