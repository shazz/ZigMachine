/* Present a W x H ARGB8888 picture on plane 0 as 8-bit pixels. Opt-in (src/opt); kestrel_render.c's
 * SDL_RenderPresent calls it. The palette is rebuilt every present from that picture's colours (a 2048-slot
 * open hash ARGB -> index; index 0 stays black for the margins), so transient colours (alpha blends, a VU
 * meter's gradient) never use up the 256 slots for good. A picture with more than 255 colours maps the extra
 * ones to the nearest palette entry (logged once). The whole plane and palette are rewritten every present.
 * Up to 320x200 uses the normal plane; anything up to 400x280 the fullscreen (overscan) plane, centred.
 * The current SDL cursor (kestrel_render.c) is drawn on top at the mouse position, since a port that
 * draws its own pointer (kestrel_input.c drawsOwnPointer) gets none from the host.
 *
 *   kestrel_plane_init()                once from boot(): plane registers, black background
 *   kestrel_plane_origin(w, h, &x, &y)  where a w x h picture's (0,0) lands in the plane (for kestrel_input_origin)
 *   kestrel_plane_colours()             colours in the last presented picture */
#include <SDL2/SDL.h>

void kestrel_log(const char *m);
const Uint32 *kestrel_cursor_image(int *w, int *h, int *hx, int *hy);
__attribute__((import_module("env"), import_name("hwVideoBase"))) extern int hwVideoBase(void);

#define REG_BACKGROUND 0x04
#define REG_FB_STRIDE 0x34
#define REG_FB_BASE 0x44
#define REG_FB_MODE 0x54
#define OFF_PAL 0x0100
#define OFF_VRAM 0x1100
#define FB_MODE_NORMAL 0
#define FB_MODE_FULLSCREEN 1

static Uint8 *vbase;
static int pw = 320, ph = 200, ox, oy;
#define HSLOTS 2048
static Uint32 hkey[HSLOTS];
static Uint8 hval[HSLOTS], hused[HSLOTS];
static unsigned nkeys, ncolours;
static Uint32 pal_rgb[256];
static int overflow_logged;

static void palette_reset(void)
{
    memset(hused, 0, sizeof hused);
    nkeys = 0;
    ncolours = 1;
    pal_rgb[0] = 0xFF000000u;                     /* index 0 = black: the margins around the picture */
}

static Uint8 nearest(Uint32 c)
{
    int r = c >> 16 & 255, g = c >> 8 & 255, b = c & 255;
    unsigned best = 0, bd = ~0u;
    for (unsigned i = 0; i < ncolours; i++) {
        int dr = (int)(pal_rgb[i] >> 16 & 255) - r, dg = (int)(pal_rgb[i] >> 8 & 255) - g, db = (int)(pal_rgb[i] & 255) - b;
        unsigned d = (unsigned)(dr * dr + dg * dg + db * db);
        if (d < bd) { bd = d; best = i; }
    }
    return (Uint8)best;
}

static Uint8 colour_index(Uint32 c)
{
    c |= 0xFF000000u;
    unsigned h = (c * 2654435761u) >> 21;
    while (hused[h]) { if (hkey[h] == c) return hval[h]; h = (h + 1) & (HSLOTS - 1); }
    Uint8 i;
    if (c == 0xFF000000u) i = 0;
    else if (ncolours < 256) { i = (Uint8)ncolours; pal_rgb[ncolours++] = c; }
    else {
        if (!overflow_logged) { kestrel_log("kestrel_plane: a picture with more than 256 colours, extras drawn as the nearest"); overflow_logged = 1; }
        i = nearest(c);
    }
    if (nkeys < HSLOTS * 3 / 4) { hused[h] = 1; hkey[h] = c; hval[h] = i; nkeys++; }   /* else: not cached */
    return i;
}

static void plane_regs(void)
{
    vbase[REG_FB_MODE] = pw > 320 ? FB_MODE_FULLSCREEN : FB_MODE_NORMAL;
    *(Uint16 *)(vbase + REG_FB_STRIDE) = (Uint16)pw;
    *(Uint32 *)(vbase + REG_FB_BASE) = OFF_VRAM;
}

void kestrel_plane_init(void)
{
    vbase = (Uint8 *)(uintptr_t)hwVideoBase();
    *(Uint32 *)(vbase + REG_BACKGROUND) = 0xFF000000u;
    palette_reset();
}

static void plane_size(int w, int h)
{
    int full = w > 320 || h > 200;
    int npw = full ? 400 : 320, nph = full ? 280 : 200;
    if (npw == pw && nph == ph && vbase[REG_FB_MODE] == (full ? FB_MODE_FULLSCREEN : FB_MODE_NORMAL)) return;
    pw = npw; ph = nph;
    memset(vbase + OFF_VRAM, 0, (size_t)pw * (size_t)ph);
}

void kestrel_plane_origin(int w, int h, int *x, int *y)
{
    int full = w > 320 || h > 200;
    *x = ((full ? 400 : 320) - w) / 2;
    *y = ((full ? 280 : 200) - h) / 2;
}

unsigned kestrel_plane_colours(void) { return ncolours; }

static void draw_cursor(int w, int h)
{
    int cw, chh, hx, hy, mx, my;
    const Uint32 *cp = kestrel_cursor_image(&cw, &chh, &hx, &hy);
    if (!cp) return;
    SDL_GetMouseState(&mx, &my);
    for (int y = 0; y < chh; y++) {
        int py = my - hy + y;
        if (py < 0 || py >= h) continue;
        for (int x = 0; x < cw; x++) {
            int px = mx - hx + x;
            Uint32 c = cp[y * cw + x];
            if (px < 0 || px >= w || (c >> 24) < 128) continue;
            vbase[OFF_VRAM + (oy + py) * pw + ox + px] = colour_index(c);
        }
    }
}

void kestrel_plane_present(const Uint32 *src, int w, int h)
{
    if (!vbase) return;
    if (w > 400) w = 400;
    if (h > 280) h = 280;
    plane_size(w, h);
    kestrel_plane_origin(w, h, &ox, &oy);
    palette_reset();
    Uint32 last = ~0u; Uint8 li = 0;
    for (int y = 0; y < h; y++) {
        Uint8 *dst = vbase + OFF_VRAM + (oy + y) * pw + ox;
        const Uint32 *s = src + y * w;
        for (int x = 0; x < w; x++) {
            Uint32 c = s[x];
            if (c != last) { last = c; li = colour_index(c); }
            dst[x] = li;
        }
    }
    draw_cursor(w, h);
    for (unsigned i = 0; i < ncolours; i++) {
        Uint8 *p = vbase + OFF_PAL + i * 4;
        Uint32 c = pal_rgb[i];
        p[0] = (Uint8)(c >> 16); p[1] = (Uint8)(c >> 8); p[2] = (Uint8)c; p[3] = 255;
    }
    plane_regs();
}
