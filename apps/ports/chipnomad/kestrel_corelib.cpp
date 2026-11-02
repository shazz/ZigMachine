// ChipNomad's platform layer (corelib) on the ZigMachine: graphics, audio, main loop, assets.
//
// Graphics: the 40x20 text screen in the Atari ST 8x8 system font, 8x10 cells = exactly a 320x200 plane
// (plane 0, normal mode). Colours are RGB from the theme: each distinct one gets a palette index on first
// use (a 256-entry hash), so drawing writes indices straight into VRAM; nothing to present.
// Input: the shared kestrel_input.c turns the cart's key exports into SDL keycodes, which are exactly what
// ChipNomad's desktop key mapping expects (BTN_A = X, BTN_B = Z, START = Space, SELECT = Left Shift...).
// Audio: ChipNomad's callback renders one VBL of 16-bit stereo; it goes to the machine's stream ring as
// signed 8-bit mono (env.hostAudioFeed), like pt2-clone.
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL2/SDL.h>
#include "corelib_gfx.h"
#include "corelib_audio.h"
#include "corelib_mainloop.h"
#include "corelib_assets.h"

extern "C" {
__attribute__((import_module("env"), import_name("consoleLogJS"))) void consoleLogJS(const char *p, int len);
__attribute__((import_module("env"), import_name("hwVideoBase"))) int hwVideoBase(void);
__attribute__((import_module("env"), import_name("hostAudioStreamStart"))) void hostAudioStreamStart(float rate);
__attribute__((import_module("env"), import_name("hostAudioFeed"))) void hostAudioFeed(const void *p, int len);
extern const uint8_t kestrel_font8x10[95 * 10];
void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }
void kestrel_throw(const char *m) { kestrel_log("chipnomad: fatal:"); kestrel_log(m); __builtin_trap(); }
}

// --- the plane and its palette ---
#define REG_BACKGROUND 0x04
#define REG_FB_STRIDE 0x34
#define REG_FB_BASE 0x44
#define REG_FB_MODE 0x54
#define OFF_PAL 0x0100
#define OFF_VRAM 0x1100
#define SW 320
#define SH 200
#define CW 8
#define CH 10
#define COLS 40
#define ROWS 20
static uint8_t *vbase, *vram;
static uint32_t hkey[512];
static uint8_t hval[512], hused[512];
static uint32_t pal_rgb[256];
static unsigned ncolours;
static int fg, bg, cursor_c;

static uint8_t colour(uint32_t rgb)
{
    rgb &= 0xFFFFFF;
    unsigned h = (rgb * 2654435761u) >> 23;
    while (hused[h]) { if (hkey[h] == rgb) return hval[h]; h = (h + 1) & 511; }
    if (ncolours >= 256) return 0;
    uint8_t i = (uint8_t)ncolours++;
    hused[h] = 1; hkey[h] = rgb; hval[h] = i; pal_rgb[i] = rgb;
    if (vbase) { uint8_t *p = vbase + OFF_PAL + i * 4; p[0] = rgb >> 16; p[1] = rgb >> 8; p[2] = rgb; p[3] = 255; }
    return i;
}

static void fill(int x, int y, int w, int h, uint8_t c)
{
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > SW) w = SW - x;
    if (y + h > SH) h = SH - y;
    for (int r = 0; r < h; r++) memset(vram + (y + r) * SW + x, c, w > 0 ? w : 0);
}

extern "C" {
int gfxSetup(int *w, int *h)
{
    vbase = (uint8_t *)(uintptr_t)hwVideoBase();
    vram = vbase + OFF_VRAM;
    *(uint32_t *)(vbase + REG_BACKGROUND) = 0xFF000000u;
    vbase[REG_FB_MODE] = 0;                       // normal 320x200
    *(uint16_t *)(vbase + REG_FB_STRIDE) = SW;
    *(uint32_t *)(vbase + REG_FB_BASE) = OFF_VRAM;
    if (w) *w = SW;
    if (h) *h = SH;
    (void)colour(0);
    return 1;
}
// The host may reset the plane or the palette (boot ROM, a swap): re-assert them every frame.
void kestrel_gfx_frame(void)
{
    if (!vbase) return;
    vbase[REG_FB_MODE] = 0;
    *(uint16_t *)(vbase + REG_FB_STRIDE) = SW;
    *(uint32_t *)(vbase + REG_FB_BASE) = OFF_VRAM;
    for (unsigned i = 0; i < ncolours; i++) {
        uint8_t *p = vbase + OFF_PAL + i * 4; uint32_t c = pal_rgb[i];
        p[0] = c >> 16; p[1] = c >> 8; p[2] = c; p[3] = 255;
    }
}
void gfxCleanup(void) {}
void gfxSetFgColor(int rgb) { fg = rgb; }
void gfxSetBgColor(int rgb) { bg = rgb; }
void gfxSetCursorColor(int rgb) { cursor_c = rgb; }
void gfxClear(void) { fill(0, 0, SW, SH, colour(bg)); }
void gfxUpdateScreen(void) {}
void gfxClearRect(int x, int y, int w, int h) { fill(x * CW, y * CH, w * CW, h * CH, colour(bg)); }
void gfxCursor(int x, int y, int w) { fill(x * CW, y * CH + CH - 1, w * CW, 1, colour(cursor_c)); }
void gfxRect(int x, int y, int w, int h)
{
    uint8_t c = colour(fg);
    int px = x * CW, py = y * CH, pw = w * CW, ph = h * CH;
    fill(px, py, pw, 1, c); fill(px, py + ph - 1, pw, 1, c);
    fill(px, py, 1, ph, c); fill(px + pw - 1, py, 1, ph, c);
}
static void glyph(int col, int row, unsigned char ch, uint8_t f, uint8_t b)
{
    int px = col * CW, py = row * CH;
    if (px < 0 || py < 0 || px + CW > SW || py + CH > SH) return;
    const uint8_t *g = ch >= 32 && ch <= 126 ? &kestrel_font8x10[(ch - 32) * CH] : NULL;
    for (int y = 0; y < CH; y++) {
        uint8_t bits = g ? g[y] : 0, *d = vram + (py + y) * SW + px;
        for (int x = 0; x < CW; x++) d[x] = (bits & (0x80 >> x)) ? f : b;
    }
}
void gfxPrint(int x, int y, const char *text)
{
    if (!text) return;
    uint8_t f = colour(fg), b = colour(bg);
    int cx = x, cy = y;
    for (int i = 0; text[i]; i++) {
        if (text[i] == '\r' && text[i + 1] == '\n') { i++; cx = x; cy++; continue; }
        glyph(cx, cy, (unsigned char)text[i], f, b);
        if (++cx >= COLS) { cx = x; cy++; }
    }
}
void gfxPrintf(int x, int y, const char *fmt, ...)
{
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    gfxPrint(x, y, buf);
}
// Bitmaps (waveforms, characters drawn per pixel): 0..255 = background..foreground, blended in 4 steps so
// a waveform costs a handful of palette entries, not 256.
static uint8_t blend(int a)
{
    a = (a + 42) / 85;                            // 0..3
    int r = ((bg >> 16 & 255) * (3 - a) + (fg >> 16 & 255) * a) / 3;
    int g = ((bg >> 8 & 255) * (3 - a) + (fg >> 8 & 255) * a) / 3;
    int b = ((bg & 255) * (3 - a) + (fg & 255) * a) / 3;
    return colour((uint32_t)(r << 16 | g << 8 | b));
}
void gfxDrawCharBitmap(uint8_t *bm, int col, int row)
{
    int px = col * CW, py = row * CH;
    for (int y = 0; y < CH && py + y < SH; y++)
        for (int x = 0; x < CW && px + x < SW; x++) vram[(py + y) * SW + px + x] = blend(bm[y * CW + x]);
}
Bitmap *gfxBitmapCreate(int wc, int hc)
{
    Bitmap *b = (Bitmap *)malloc(sizeof(Bitmap));
    if (!b) return NULL;
    b->widthChars = wc; b->heightChars = hc; b->widthPixels = wc * CW; b->heightPixels = hc * CH;
    b->data = (uint8_t *)calloc((size_t)b->widthPixels * b->heightPixels, 1);
    b->userdata = NULL;
    if (!b->data) { free(b); return NULL; }
    return b;
}
void gfxBitmapClear(Bitmap *b) { memset(b->data, 0, (size_t)b->widthPixels * b->heightPixels); }
void gfxBitmapFree(Bitmap *b) { if (b) { free(b->data); free(b); } }
void gfxDrawBitmap(Bitmap *bm, int col, int row)
{
    if (!bm || !bm->data) return;
    int px = col * CW, py = row * CH;
    for (int y = 0; y < bm->heightPixels && py + y < SH; y++)
        for (int x = 0; x < bm->widthPixels && px + x < SW; x++)
            vram[(py + y) * SW + px + x] = blend(bm->data[y * bm->widthPixels + x]);
}
int gfxGetCharWidth(void) { return CW; }
int gfxGetCharHeight(void) { return CH; }
void gfxReloadFont(void) {}
void gfxDrawHUD(void) {}
void gfxSetButtonPressed(int i, int p) { (void)i; (void)p; }
void gfxPoint(int x, int y, uint32_t c) { if (x >= 0 && y >= 0 && x < SW && y < SH) vram[y * SW + x] = colour(c); }

int assetsInit(void) { return 0; }

// --- audio ---
static AudioCallback *audio_cb;
static int audio_rate = 48000, audio_paused = 1, stream_on;
static int16_t mixbuf[2 * 1024];
static int8_t outbuf[1024];
int audioSetup(AudioCallback *cb, int rate, int bufsize) { (void)bufsize; audio_cb = cb; audio_rate = rate; return 1; }
void audioPause(int p) { audio_paused = p; }
void audioCleanup(void) { audio_cb = NULL; }
void kestrel_audio_frame(void)
{
    if (!audio_cb) return;
    int n = audio_rate / 60;
    if (n > 1024) n = 1024;
    if (!stream_on) { hostAudioStreamStart((float)audio_rate); stream_on = 1; }
    if (audio_paused) memset(mixbuf, 0, sizeof mixbuf);
    else audio_cb(mixbuf, n);
    for (int i = 0; i < n; i++) {
        int m = ((int)mixbuf[2 * i] + (int)mixbuf[2 * i + 1]) >> 9;
        outbuf[i] = (int8_t)(m > 127 ? 127 : m < -128 ? -128 : m);
    }
    hostAudioFeed(outbuf, n);
}

// --- what the shared SDL layer needs from a port ---
static uint64_t micros;
void kestrel_sdl_vbl(void) { micros += 1000000 / 60; }
Uint64 SDL_GetPerformanceCounter(void) { return micros; }
Uint32 SDL_GetTicks(void) { return (Uint32)(micros / 1000); }
const char *SDL_GetKeyName(SDL_Keycode k)
{
    static char b[8];
    if (k >= 32 && k < 127) { b[0] = (char)(k >= 'a' && k <= 'z' ? k - 32 : k); b[1] = 0; return b; }
    switch (k) {
    case SDLK_UP: return "Up"; case SDLK_DOWN: return "Down"; case SDLK_LEFT: return "Left"; case SDLK_RIGHT: return "Right";
    default: return "";
    }
}
}

// --- main loop (C++ linkage, as corelib_mainloop.h declares it) ---
void mainLoopRun(void (*draw)(void), void (*onEvent)(MainLoopEventData)) { (void)draw; (void)onEvent; }
void mainLoopDelay(int ms) { (void)ms; }
void mainLoopQuit(void) {}
static int quit_requested;
void mainLoopTriggerQuit(void) { quit_requested = 1; }
extern "C" int kestrel_quit_requested(void) { return quit_requested; }

