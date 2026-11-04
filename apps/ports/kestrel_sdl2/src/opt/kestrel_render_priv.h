/* Shared between the opt-in renderer modules: kestrel_render.c (surfaces, textures, ARGB targets),
 * kestrel_window8.c (the window drawn as 8-bit indices), kestrel_palette.c (ARGB -> index) and kestrel_plane.c
 * (the indices shown on plane 0). Not part of the SDL API. */
#ifndef KESTREL_RENDER_PRIV_H
#define KESTREL_RENDER_PRIV_H
#include <SDL2/SDL.h>

/* A texture: ARGB (px) or, with at most 256 colours, 8-bit (idx + pal, npal colours). mpal = pal with the colour
 * mod applied (cache, kestrel_mod_palette); gmap = that palette as window indices (cache, kestrel_window8.c). */
struct SDL_Texture {
    int w, h, access; Uint32 *px; Uint8 *idx; Uint32 *pal; Uint8 mr, mg, mb; SDL_BlendMode blend;
    int npal; Uint32 *mpal; Uint8 pmr, pmg, pmb;
    Uint16 *gmap; Uint32 gkey; unsigned ggen; int gall, gpart;
    unsigned serial;                    /* new for each content (kestrel_texture_touched): the defer hash's name */
};

/* The same blend as SDL's software renderer (d = destination, s = source ARGB, a = its alpha). */
static inline Uint32 kestrel_blend_px(Uint32 d, Uint32 s, unsigned a, SDL_BlendMode m)
{
    unsigned sr = s >> 16 & 255, sg = s >> 8 & 255, sb = s & 255;
    unsigned dr = d >> 16 & 255, dg = d >> 8 & 255, db = d & 255;
    if (m == SDL_BLENDMODE_MOD) { dr = dr * sr / 255; dg = dg * sg / 255; db = db * sb / 255; }
    else if (m == SDL_BLENDMODE_ADD) {
        dr += sr * a / 255; dg += sg * a / 255; db += sb * a / 255;
        if (dr > 255) dr = 255;
        if (dg > 255) dg = 255;
        if (db > 255) db = 255;
    } else if (a >= 255) return s | 0xFF000000u;
    else { dr = (sr * a + dr * (255 - a)) / 255; dg = (sg * a + dg * (255 - a)) / 255; db = (sb * a + db * (255 - a)) / 255; }
    return 0xFF000000u | dr << 16 | dg << 8 | db;
}

int kestrel_clip_rect(SDL_Rect *d, int *sx, int *sy, int w, int h, const SDL_Rect *clip);
const Uint32 *kestrel_mod_palette(SDL_Texture *t);

/* kestrel_palette.c: the window's palette, kept across presents (index 0 = black). */
extern Uint32 kestrel_pal_rgb[256];        /* index -> ARGB (alpha 255) */
extern unsigned kestrel_pal_n;             /* entries in use */
extern unsigned kestrel_pal_gen;           /* bumped when a compaction renumbered the indices */
Uint8 kestrel_colour_index(Uint32 argb);
enum { KPAL_WINDOW, KPAL_SHOWN };
void kestrel_palette_track(int slot, Uint8 *buf, unsigned n);   /* index buffers a compaction must renumber */
void kestrel_palette_presented(void);     /* once a present: a full palette may be compacted again */
extern int kestrel_palette_compacted;      /* set by a compaction: the plane must rewrite everything */

/* kestrel_window8.c: drawing into the window's 8-bit buffer (fb8, pitch w). */
void kestrel_w8_clear(Uint8 *fb, int w, int h, Uint32 c);
void kestrel_w8_fill(Uint8 *fb, int w, const SDL_Rect *d, Uint32 c, unsigned a, SDL_BlendMode m);
void kestrel_w8_line(Uint8 *fb, int w, int h, const SDL_Rect *clip, int x1, int y1, int x2, int y2, Uint32 c);
void kestrel_w8_copy(SDL_Texture *tex, Uint8 *fb, int w, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy,
                     Uint32 stepx, Uint32 stepy);

int kestrel_w8_idempotent(SDL_Texture *tex, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy);

/* kestrel_defer.c: the window's drawing recorded, replayed at the present only where it changed. */
void kestrel_defer_target(Uint8 *fb, int w, int h);
void kestrel_defer_copy(SDL_Texture *t, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy);
void kestrel_defer_fill(const SDL_Rect *d, Uint32 c, unsigned a, SDL_BlendMode m);
void kestrel_defer_clear(Uint32 c);
void kestrel_defer_line(const SDL_Rect *clip, int x1, int y1, int x2, int y2, Uint32 c);
void kestrel_defer_present(void);
int kestrel_defer_row_changed(int y);
void kestrel_texture_touched(SDL_Texture *t);   /* before a texture's pixels change or it is freed */

/* kestrel_plane.c */
void kestrel_plane_present8(const Uint8 *src, int w, int h);
#endif
