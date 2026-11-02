/* SDL_image's IMG_Load / IMG_Load_RW on the cart through stb_image (third_party/stb, pinned: see VERSION there).
 * Opt-in (src/opt); the port also defines KESTREL_SDL_IMAGE so SDL_image.h declares these instead of its
 * NULL-returning stubs. PNG, GIF, BMP, TGA. An image of at most 256 colours becomes an INDEX8 surface (as
 * SDL_image returns for a palette PNG; a quarter of the memory), any other an ARGB8888 one (kestrel_render.c);
 * alpha is kept either way.
 * The stream is read whole first (RWops from bundles report no size), then decoded from memory. */
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>

void kestrel_log(const char *m);
SDL_Surface *kestrel_surface_index8(int w, int h, const Uint32 *pal, int n, int alpha);

#define STBI_NO_STDIO
#define STBI_ONLY_PNG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_ONLY_TGA
#define STBI_NO_SIMD
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_ASSERT(x) ((void)0)
#define STB_IMAGE_IMPLEMENTATION
#include "../../third_party/stb/stb_image.h"

static Uint8 *read_all(SDL_RWops *rw, int *len)
{
    size_t cap = 16384, n = 0;
    Uint8 *buf = malloc(cap);
    while (buf) {
        if (n == cap) {
            Uint8 *b = realloc(buf, cap * 2);
            if (!b) { free(buf); return NULL; }
            buf = b; cap *= 2;
        }
        size_t got = SDL_RWread(rw, buf + n, 1, cap - n);
        if (got == 0) break;
        n += got;
    }
    *len = (int)n;
    return buf;
}

static inline Uint32 argb(const stbi_uc *p) { return (Uint32)p[3] << 24 | (Uint32)p[0] << 16 | (Uint32)p[1] << 8 | p[2]; }

/* The INDEX8 form when the image has at most 256 colours, else NULL. */
static SDL_Surface *to_index8(const stbi_uc *rgba, int w, int h, int alpha)
{
    Uint32 pal[256], hk[512]; Uint16 hv[512]; Uint8 hu[512] = { 0 };
    int n = 0;
    for (int i = 0; i < w * h; i++) {
        Uint32 c = argb(rgba + i * 4);
        unsigned k = (c * 2654435761u) >> 23;
        while (hu[k] && hk[k] != c) k = (k + 1) & 511;
        if (!hu[k]) { if (n == 256) return NULL; hu[k] = 1; hk[k] = c; hv[k] = (Uint16)n; pal[n++] = c; }
    }
    SDL_Surface *s = kestrel_surface_index8(w, h, pal, n, alpha);
    if (!s) return NULL;
    Uint8 *px = s->pixels;
    for (int i = 0; i < w * h; i++) {
        Uint32 c = argb(rgba + i * 4);
        unsigned k = (c * 2654435761u) >> 23;
        while (hk[k] != c) k = (k + 1) & 511;
        px[i] = (Uint8)hv[k];
    }
    return s;
}

SDL_Surface *IMG_Load_RW(SDL_RWops *rw, int freesrc)
{
    if (!rw) return NULL;
    int len = 0, w, h, comp;
    Uint8 *data = read_all(rw, &len);
    if (freesrc) SDL_RWclose(rw);
    if (!data) { kestrel_log("IMG_Load: out of memory reading the image"); return NULL; }
    stbi_uc *rgba = stbi_load_from_memory(data, len, &w, &h, &comp, 4);
    free(data);
    if (!rgba) { kestrel_log("IMG_Load: stb_image could not decode the image"); return NULL; }
    int alpha = comp == 4 || comp == 2;
    SDL_Surface *s = to_index8(rgba, w, h, alpha);
    if (!s && (s = SDL_CreateRGBSurface(0, w, h, 32, 0x00FF0000u, 0x0000FF00u, 0x000000FFu, alpha ? 0xFF000000u : 0))) {
        Uint32 *px = s->pixels;
        for (int i = 0; i < w * h; i++) px[i] = argb(rgba + i * 4);
    }
    stbi_image_free(rgba);
    return s;
}

SDL_Surface *IMG_Load(const char *file) { return IMG_Load_RW(SDL_RWFromFile(file, "rb"), 1); }
const SDL_version *IMG_Linked_Version(void) { static const SDL_version v = { 2, 0, 0 }; return &v; }
