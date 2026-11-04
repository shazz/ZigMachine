/* A small software SDL_Renderer for the cart, plus the SDL_Surface and SDL_Cursor calls around it. Opt-in
 * (src/opt): pt2 and GrafX2 define their own stubs for these, so only a port that lists this file links it.
 *
 * Surfaces come in two layouts: 32-bit ARGB8888 (A in the top byte) whatever masks the program asks for, and
 * 8-bit INDEX8 with a 256-colour palette (depth 8, and what IMG_Load returns for an image of <= 256 colours, as
 * SDL_image does for a palette PNG: a quarter of the memory). SDL_MapRGB / SDL_GetRGB / SDL_FillRect /
 * SDL_GetColorKey agree with each layout, so programs that go through them (or read pixels by
 * format->BytesPerPixel, as klystron does) never notice. Blits into a surface support ARGB destinations only.
 * A texture is a copy of its surface with the colour key turned into alpha 0, itself 8-bit when it has at most
 * 256 colours. A renderer draws into its target: a TARGET texture, its software surface, or by default a
 * window-sized 8-bit buffer of palette indices (kestrel_window8.c, kestrel_palette.c) that SDL_RenderPresent
 * hands to kestrel_plane_present8() (kestrel_plane.c) and then to the port's kestrel_present_hook (e.g. an
 * Asyncify yield). Supported: colour mod, NONE / BLEND / ADD / MOD
 * blending, nearest-neighbour scaling, clip rect, viewport offset. Not supported: rotation, render scale != 1
 * (logged). */
#include "kestrel_render_priv.h"

void kestrel_log(const char *m);
void (*kestrel_present_hook)(void);

static SDL_PixelFormat argb_format = {
    SDL_PIXELFORMAT_ARGB8888, NULL, 32, 4, { 0, 0 }, 0x00FF0000u, 0x0000FF00u, 0x000000FFu, 0xFF000000u,
    0, 0, 0, 0, 16, 8, 0, 24
};

/* --- surfaces: the SDL_Surface heads a block that also carries the colour key, blend mode and, for INDEX8,
 * the format and palette --- */
typedef struct {
    SDL_Surface s; Uint32 key; int has_key; SDL_BlendMode blend;
    SDL_PixelFormat fmt8; SDL_Palette pal; SDL_Color colors[256];
} ksurf_t;
#define KS(p) ((ksurf_t *)(p))
#define IS8(s) ((s)->format->BytesPerPixel == 1)

static SDL_Surface *new_surface(int w, int h, int bpp, int alpha)
{
    if (w <= 0 || h <= 0) return NULL;
    ksurf_t *k = calloc(1, sizeof *k);
    if (!k) return NULL;
    k->s.pixels = calloc((size_t)w * (size_t)h, (size_t)bpp);
    if (!k->s.pixels) { free(k); return NULL; }
    if (bpp == 1) {
        k->pal = (SDL_Palette){ 256, k->colors, 0, 1 };
        k->fmt8 = (SDL_PixelFormat){ SDL_PIXELFORMAT_INDEX8, &k->pal, 8, 1, { 0, 0 }, 0, 0, 0, 0, 8, 8, 8, 8, 0, 0, 0, 0 };
        for (int i = 0; i < 256; i++) k->colors[i] = (SDL_Color){ (Uint8)i, (Uint8)i, (Uint8)i, 255 };
        k->s.format = &k->fmt8;
    } else k->s.format = &argb_format;
    k->s.w = w; k->s.h = h; k->s.pitch = w * bpp;
    k->s.clip_rect = (SDL_Rect){ 0, 0, w, h };
    k->blend = alpha ? SDL_BLENDMODE_BLEND : SDL_BLENDMODE_NONE;
    return &k->s;
}
SDL_Surface *SDL_CreateRGBSurface(Uint32 f, int w, int h, int d, Uint32 rm, Uint32 gm, Uint32 bm, Uint32 am)
{
    (void)f; (void)rm; (void)gm; (void)bm;
    return new_surface(w, h, d == 8 ? 1 : 4, am != 0);
}
/* For kestrel_image.c: an INDEX8 surface with the n colours of pal (ARGB). */
SDL_Surface *kestrel_surface_index8(int w, int h, const Uint32 *pal, int n, int alpha)
{
    SDL_Surface *s = new_surface(w, h, 1, alpha);
    if (!s) return NULL;
    for (int i = 0; i < n; i++) KS(s)->colors[i] = (SDL_Color){ (Uint8)(pal[i] >> 16), (Uint8)(pal[i] >> 8), (Uint8)pal[i], (Uint8)(pal[i] >> 24) };
    return s;
}
int SDL_SetPaletteColors(SDL_Palette *p, const SDL_Color *c, int first, int n)
{
    if (!p || first < 0 || first + n > p->ncolors) return -1;
    memcpy(p->colors + first, c, (size_t)n * sizeof *c);
    p->version++;
    return 0;
}
void SDL_FreeSurface(SDL_Surface *s) { if (s) { free(s->pixels); free(KS(s)); } }
int SDL_LockSurface(SDL_Surface *s) { (void)s; return 0; }
void SDL_UnlockSurface(SDL_Surface *s) { (void)s; }
int SDL_SetSurfaceRLE(SDL_Surface *s, int f) { (void)s; (void)f; return 0; }
int SDL_SetSurfaceBlendMode(SDL_Surface *s, SDL_BlendMode m) { if (!s) return -1; KS(s)->blend = m; return 0; }
Uint32 SDL_MapRGB(const SDL_PixelFormat *f, Uint8 r, Uint8 g, Uint8 b)
{
    if (!f || !f->palette) return 0xFF000000u | (Uint32)r << 16 | (Uint32)g << 8 | b;
    Uint32 best = 0, bd = ~0u;                     /* palette: the exact or nearest colour, as SDL */
    for (int i = 0; i < f->palette->ncolors; i++) {
        const SDL_Color *c = &f->palette->colors[i];
        Uint32 d = (Uint32)((c->r - r) * (c->r - r) + (c->g - g) * (c->g - g) + (c->b - b) * (c->b - b));
        if (d < bd) { bd = d; best = (Uint32)i; if (!d) break; }
    }
    return best;
}
void SDL_GetRGB(Uint32 p, const SDL_PixelFormat *f, Uint8 *r, Uint8 *g, Uint8 *b)
{
    if (f && f->palette) { const SDL_Color *c = &f->palette->colors[p & 255]; *r = c->r; *g = c->g; *b = c->b; return; }
    *r = (Uint8)(p >> 16); *g = (Uint8)(p >> 8); *b = (Uint8)p;
}
int SDL_SetColorKey(SDL_Surface *s, int flag, Uint32 key)
{
    if (!s) return -1;
    KS(s)->has_key = flag != 0; KS(s)->key = key;
    if (flag) KS(s)->blend = SDL_BLENDMODE_BLEND;
    return 0;
}
int SDL_GetColorKey(SDL_Surface *s, Uint32 *key) { if (!s || !KS(s)->has_key) return -1; if (key) *key = KS(s)->key; return 0; }

/* Pixel (x, y) as ARGB the way a texture holds it: the key -> transparent 0, no alpha channel -> opaque. */
static inline Uint32 surf_value(SDL_Surface *s, int x, int y)
{
    ksurf_t *k = KS(s);
    if (IS8(s)) {
        Uint8 i = ((const Uint8 *)s->pixels)[y * s->pitch + x];
        if (k->has_key && i == (k->key & 255)) return 0;
        const SDL_Color *c = &k->colors[i];
        Uint32 a = k->blend == SDL_BLENDMODE_BLEND ? c->a : 255;
        return a << 24 | (Uint32)c->r << 16 | (Uint32)c->g << 8 | c->b;
    }
    Uint32 c = ((const Uint32 *)((const Uint8 *)s->pixels + y * s->pitch))[x];
    if (k->has_key && (c & 0xFFFFFFu) == (k->key & 0xFFFFFFu)) return 0;
    return k->blend == SDL_BLENDMODE_BLEND ? c : c | 0xFF000000u;
}

SDL_Surface *SDL_ConvertSurfaceFormat(SDL_Surface *s, Uint32 format, Uint32 flags)
{
    (void)format; (void)flags;                     /* always to ARGB8888 */
    SDL_Surface *c = new_surface(s->w, s->h, 4, 1);
    if (!c) return NULL;
    for (int y = 0; y < s->h; y++) for (int x = 0; x < s->w; x++) ((Uint32 *)c->pixels)[y * s->w + x] = surf_value(s, x, y);
    if (!KS(s)->has_key && KS(s)->blend != SDL_BLENDMODE_BLEND) KS(c)->blend = SDL_BLENDMODE_NONE;
    return c;
}

/* Clip *d (and the matching source origin) to the w x h target and an optional clip rect: 0 = nothing left. */
int kestrel_clip_rect(SDL_Rect *d, int *sx, int *sy, int w, int h, const SDL_Rect *clip)
{
    int x0 = 0, y0 = 0, x1 = w, y1 = h;
    if (clip) {
        if (clip->x > x0) x0 = clip->x;
        if (clip->y > y0) y0 = clip->y;
        if (clip->x + clip->w < x1) x1 = clip->x + clip->w;
        if (clip->y + clip->h < y1) y1 = clip->y + clip->h;
    }
    if (d->x < x0) { if (sx) *sx += x0 - d->x; d->w -= x0 - d->x; d->x = x0; }
    if (d->y < y0) { if (sy) *sy += y0 - d->y; d->h -= y0 - d->y; d->y = y0; }
    if (d->x + d->w > x1) d->w = x1 - d->x;
    if (d->y + d->h > y1) d->h = y1 - d->y;
    return d->w > 0 && d->h > 0;
}

int SDL_FillRect(SDL_Surface *s, const SDL_Rect *r, Uint32 c)
{
    if (!s) return -1;
    SDL_Rect d = r ? *r : (SDL_Rect){ 0, 0, s->w, s->h };
    if (!kestrel_clip_rect(&d, NULL, NULL, s->w, s->h, &s->clip_rect)) return 0;
    for (int y = d.y; y < d.y + d.h; y++) {
        if (IS8(s)) { memset((Uint8 *)s->pixels + y * s->pitch + d.x, (int)(c & 255), (size_t)d.w); continue; }
        Uint32 *p = (Uint32 *)((Uint8 *)s->pixels + y * s->pitch) + d.x;
        for (int x = 0; x < d.w; x++) p[x] = c;
    }
    return 0;
}

static int argb_dest(SDL_Surface *dst)
{
    if (!IS8(dst)) return 1;
    kestrel_log("SDL_BlitSurface: blits into an 8-bit surface are not supported");
    return 0;
}
/* Unscaled surface blit into an ARGB surface: key / alpha honoured as transparency (no partial alpha). */
int SDL_BlitSurface(SDL_Surface *src, const SDL_Rect *sr, SDL_Surface *dst, SDL_Rect *dr)
{
    if (!argb_dest(dst)) return -1;
    SDL_Rect s = sr ? *sr : (SDL_Rect){ 0, 0, src->w, src->h };
    SDL_Rect d = { dr ? dr->x : 0, dr ? dr->y : 0, s.w, s.h };
    int sx = s.x, sy = s.y;
    if (!kestrel_clip_rect(&d, &sx, &sy, dst->w, dst->h, &dst->clip_rect)) return 0;
    for (int y = 0; y < d.h; y++) {
        Uint32 *dp = (Uint32 *)((Uint8 *)dst->pixels + (d.y + y) * dst->pitch) + d.x;
        for (int x = 0; x < d.w; x++) {
            Uint32 c = surf_value(src, sx + x, sy + y);
            if ((c >> 24) >= 128) dp[x] = c | 0xFF000000u;
        }
    }
    if (dr) *dr = d;
    return 0;
}
int SDL_BlitScaled(SDL_Surface *src, const SDL_Rect *sr, SDL_Surface *dst, SDL_Rect *dr)
{
    if (!argb_dest(dst)) return -1;
    SDL_Rect s = sr ? *sr : (SDL_Rect){ 0, 0, src->w, src->h };
    SDL_Rect d = dr ? *dr : (SDL_Rect){ 0, 0, dst->w, dst->h };
    if (s.w <= 0 || s.h <= 0 || d.w <= 0 || d.h <= 0) return 0;
    for (int y = 0; y < d.h; y++) {
        int ty = d.y + y;
        if (ty < 0 || ty >= dst->h) continue;
        Uint32 *dp = (Uint32 *)((Uint8 *)dst->pixels + ty * dst->pitch);
        for (int x = 0; x < d.w; x++) {
            int tx = d.x + x;
            if (tx >= 0 && tx < dst->w) dp[tx] = surf_value(src, s.x + x * s.w / d.w, s.y + y * s.h / d.h) | 0xFF000000u;
        }
    }
    return 0;
}

/* --- textures ---
 * A texture made from a surface with at most 256 distinct ARGB values (after the key is made transparent) is
 * kept as 8-bit indices + a 256-entry palette: a quarter of the memory, and theme art (fonts, bevels) always
 * qualifies. Other textures, and render targets, are ARGB. */
/* struct SDL_Texture: kestrel_render_priv.h */

SDL_Texture *SDL_CreateTexture(SDL_Renderer *r, Uint32 format, int access, int w, int h)
{
    (void)r; (void)format;
    if (w <= 0 || h <= 0) return NULL;
    SDL_Texture *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->px = calloc((size_t)w * (size_t)h, 4);
    if (!t->px) { free(t); return NULL; }
    t->w = w; t->h = h; t->access = access; t->mr = t->mg = t->mb = 255; t->blend = SDL_BLENDMODE_NONE;
    kestrel_texture_touched(t);
    return t;
}

/* Try the 8-bit form: 1 when it fits in 256 colours (t->idx / t->pal filled), 0 to fall back to ARGB. */
static int make_indexed(SDL_Texture *t, SDL_Surface *s)
{
    Uint32 hk[512]; Uint16 hv[512]; Uint8 hu[512] = { 0 };
    unsigned n = 0;
    Uint8 *idx = malloc((size_t)s->w * (size_t)s->h);
    Uint32 *pal = malloc(256 * 4);
    if (!idx || !pal) { free(idx); free(pal); return 0; }
    if (IS8(s)) {   /* an INDEX8 surface: hash each surface index once, then one table read a pixel (same result) */
        Uint16 map[256];
        memset(map, 0xFF, sizeof map);
        for (int y = 0; y < s->h; y++) {
            const Uint8 *row = (const Uint8 *)s->pixels + y * s->pitch;
            for (int x = 0; x < s->w; x++) {
                Uint8 i = row[x];
                if (map[i] == 0xFFFF) {
                    Uint32 c = surf_value(s, x, y);
                    unsigned h = (c * 2654435761u) >> 23;
                    while (hu[h] && hk[h] != c) h = (h + 1) & 511;
                    if (!hu[h]) { hu[h] = 1; hk[h] = c; hv[h] = (Uint16)n; pal[n++] = c; }
                    map[i] = hv[h];
                }
                idx[y * s->w + x] = (Uint8)map[i];
            }
        }
        t->idx = idx; t->pal = pal; t->npal = (int)n;
        return 1;
    }
    for (int y = 0; y < s->h; y++) {
        for (int x = 0; x < s->w; x++) {
            Uint32 c = surf_value(s, x, y);
            unsigned h = (c * 2654435761u) >> 23;
            while (hu[h] && hk[h] != c) h = (h + 1) & 511;
            if (!hu[h]) {
                if (n == 256) { free(idx); free(pal); return 0; }
                hu[h] = 1; hk[h] = c; hv[h] = (Uint16)n; pal[n++] = c;
            }
            idx[y * s->w + x] = (Uint8)hv[h];
        }
    }
    t->idx = idx; t->pal = pal; t->npal = (int)n;
    return 1;
}

SDL_Texture *SDL_CreateTextureFromSurface(SDL_Renderer *r, SDL_Surface *s)
{
    (void)r;
    if (!s) return NULL;
    SDL_Texture *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->w = s->w; t->h = s->h; t->access = SDL_TEXTUREACCESS_STATIC; t->mr = t->mg = t->mb = 255;
    kestrel_texture_touched(t);
    t->blend = KS(s)->has_key || KS(s)->blend == SDL_BLENDMODE_BLEND ? SDL_BLENDMODE_BLEND : SDL_BLENDMODE_NONE;
    if (make_indexed(t, s)) return t;
    t->px = malloc((size_t)s->w * (size_t)s->h * 4);
    if (!t->px) { free(t); return NULL; }
    for (int y = 0; y < s->h; y++) for (int x = 0; x < s->w; x++) t->px[y * t->w + x] = surf_value(s, x, y);
    return t;
}
void SDL_DestroyTexture(SDL_Texture *t) { if (t) { kestrel_texture_touched(t); free(t->px); free(t->idx); free(t->pal); free(t->mpal); free(t->gmap); free(t); } }
int SDL_SetTextureBlendMode(SDL_Texture *t, SDL_BlendMode m) { if (!t) return -1; t->blend = m; return 0; }
int SDL_SetTextureColorMod(SDL_Texture *t, Uint8 r, Uint8 g, Uint8 b) { if (!t) return -1; t->mr = r; t->mg = g; t->mb = b; return 0; }
int SDL_SetTextureScaleMode(SDL_Texture *t, SDL_ScaleMode m) { (void)t; (void)m; return 0; }
int SDL_UpdateTexture(SDL_Texture *t, const SDL_Rect *rect, const void *px, int pitch)
{
    kestrel_texture_touched(t);
    if (!t->px) {                                   /* an indexed texture being written: back to ARGB first */
        Uint32 *argb = malloc((size_t)t->w * (size_t)t->h * 4);
        if (!argb) return -1;
        for (int i = 0; i < t->w * t->h; i++) argb[i] = t->pal[t->idx[i]];
        free(t->idx); free(t->pal); free(t->mpal); free(t->gmap); t->idx = NULL; t->pal = NULL; t->mpal = NULL; t->gmap = NULL; t->px = argb;
    }
    SDL_Rect d = rect ? *rect : (SDL_Rect){ 0, 0, t->w, t->h };
    int sx = 0, sy = 0;
    if (!kestrel_clip_rect(&d, &sx, &sy, t->w, t->h, NULL)) return 0;
    for (int y = 0; y < d.h; y++) memcpy(t->px + (d.y + y) * t->w + d.x, (const Uint8 *)px + (sy + y) * pitch + sx * 4, (size_t)d.w * 4);
    return 0;
}

/* --- renderers --- */
struct SDL_Renderer {
    SDL_Surface *surface;               /* software renderer target, or NULL: the window buffer below */
    Uint8 *fb8; int fw, fh;             /* the window: palette indices (kestrel_window8.c) */
    SDL_Texture *target;
    Uint8 dr, dg, db, da; SDL_BlendMode draw_blend;
    SDL_Rect clip; int clip_on;
    int vx, vy;                         /* viewport origin */
};
typedef struct { Uint32 *px; int w, h, pitch; } tgt_t;  /* pitch in pixels; px NULL: the 8-bit window */

static tgt_t target_of(SDL_Renderer *r)
{
    if (r->target && r->target->px) return (tgt_t){ r->target->px, r->target->w, r->target->h, r->target->w };
    if (r->surface) return (tgt_t){ r->surface->pixels, r->surface->w, r->surface->h, r->surface->pitch / 4 };
    return (tgt_t){ NULL, r->fw, r->fh, r->fw };
}

SDL_Renderer *SDL_CreateRenderer(SDL_Window *w, int index, Uint32 flags)
{
    (void)index; (void)flags;
    int ww = 320, hh = 200;
    SDL_GetWindowSize(w, &ww, &hh);
    SDL_Renderer *r = calloc(1, sizeof *r);
    if (!r) return NULL;
    r->fb8 = calloc((size_t)ww * (size_t)hh, 1);
    if (!r->fb8) { free(r); return NULL; }
    r->fw = ww; r->fh = hh; r->da = 255;
    kestrel_palette_track(KPAL_WINDOW, r->fb8, (unsigned)(ww * hh));
    kestrel_defer_target(r->fb8, ww, hh);
    return r;
}
SDL_Renderer *SDL_CreateSoftwareRenderer(SDL_Surface *s)
{
    if (!s) return NULL;
    if (IS8(s)) { kestrel_log("SDL_CreateSoftwareRenderer: 8-bit target surfaces are not supported"); return NULL; }
    SDL_Renderer *r = calloc(1, sizeof *r);
    if (r) { r->surface = s; r->da = 255; }
    return r;
}
void SDL_DestroyRenderer(SDL_Renderer *r)
{
    if (!r) return;
    if (r->fb8) { kestrel_palette_track(KPAL_WINDOW, NULL, 0); kestrel_defer_target(NULL, 0, 0); }
    free(r->fb8);
    free(r);
}
int SDL_GetRendererInfo(SDL_Renderer *r, SDL_RendererInfo *info)
{
    (void)r;
    memset(info, 0, sizeof *info);
    info->name = "kestrel";
    info->flags = SDL_RENDERER_SOFTWARE | SDL_RENDERER_TARGETTEXTURE;
    info->num_texture_formats = 1;
    info->texture_formats[0] = SDL_PIXELFORMAT_ARGB8888;
    info->max_texture_width = info->max_texture_height = 4096;
    return 0;
}
int SDL_SetRenderTarget(SDL_Renderer *r, SDL_Texture *t) { if (t) kestrel_texture_touched(t); r->target = t; r->clip_on = 0; r->vx = r->vy = 0; return 0; }
int SDL_RenderSetViewport(SDL_Renderer *r, const SDL_Rect *v) { r->vx = v ? v->x : 0; r->vy = v ? v->y : 0; return 0; }
int SDL_RenderSetScale(SDL_Renderer *r, float sx, float sy)
{
    (void)r;
    if (sx != 1.0f || sy != 1.0f) kestrel_log("SDL_RenderSetScale: only scale 1 is supported");
    return 0;
}
int SDL_RenderSetClipRect(SDL_Renderer *r, const SDL_Rect *c)
{
    r->clip_on = c != NULL;
    if (c) r->clip = (SDL_Rect){ c->x + r->vx, c->y + r->vy, c->w, c->h };
    return 0;
}
void SDL_RenderGetClipRect(SDL_Renderer *r, SDL_Rect *c)
{
    if (r->clip_on) *c = (SDL_Rect){ r->clip.x - r->vx, r->clip.y - r->vy, r->clip.w, r->clip.h };
    else *c = (SDL_Rect){ 0, 0, 0, 0 };
}
int SDL_SetRenderDrawColor(SDL_Renderer *r, Uint8 cr, Uint8 cg, Uint8 cb, Uint8 ca) { r->dr = cr; r->dg = cg; r->db = cb; r->da = ca; return 0; }
int SDL_SetRenderDrawBlendMode(SDL_Renderer *r, SDL_BlendMode m) { r->draw_blend = m; return 0; }

int SDL_RenderClear(SDL_Renderer *r)
{
    tgt_t t = target_of(r);
    Uint32 c = 0xFF000000u | (Uint32)r->dr << 16 | (Uint32)r->dg << 8 | r->db;
    if (!t.px) { kestrel_defer_clear(c); return 0; }
    for (int y = 0; y < t.h; y++) for (int x = 0; x < t.w; x++) t.px[y * t.pitch + x] = c;
    return 0;
}

int SDL_RenderFillRect(SDL_Renderer *r, const SDL_Rect *rect)
{
    tgt_t t = target_of(r);
    SDL_Rect d = rect ? (SDL_Rect){ rect->x + r->vx, rect->y + r->vy, rect->w, rect->h } : (SDL_Rect){ r->vx, r->vy, t.w, t.h };
    if (!kestrel_clip_rect(&d, NULL, NULL, t.w, t.h, r->clip_on ? &r->clip : NULL)) return 0;
    Uint32 c = 0xFF000000u | (Uint32)r->dr << 16 | (Uint32)r->dg << 8 | r->db;
    if (!t.px) { kestrel_defer_fill(&d, c, r->da, r->draw_blend); return 0; }
    int opaque = r->draw_blend == SDL_BLENDMODE_NONE || (r->draw_blend == SDL_BLENDMODE_BLEND && r->da == 255);
    for (int y = d.y; y < d.y + d.h; y++) {
        Uint32 *p = t.px + y * t.pitch + d.x;
        if (opaque) for (int x = 0; x < d.w; x++) p[x] = c;
        else for (int x = 0; x < d.w; x++) p[x] = kestrel_blend_px(p[x], c, r->da, r->draw_blend);
    }
    return 0;
}

int SDL_RenderDrawLine(SDL_Renderer *r, int x1, int y1, int x2, int y2)
{
    tgt_t t = target_of(r);
    Uint32 c = 0xFF000000u | (Uint32)r->dr << 16 | (Uint32)r->dg << 8 | r->db;
    x1 += r->vx; x2 += r->vx; y1 += r->vy; y2 += r->vy;
    if (!t.px) { kestrel_defer_line(r->clip_on ? &r->clip : NULL, x1, y1, x2, y2, c); return 0; }
    int dx = abs(x2 - x1), sx = x1 < x2 ? 1 : -1, dy = -abs(y2 - y1), sy = y1 < y2 ? 1 : -1, err = dx + dy;
    for (;;) {
        int in = x1 >= 0 && y1 >= 0 && x1 < t.w && y1 < t.h;
        if (in && r->clip_on) in = x1 >= r->clip.x && y1 >= r->clip.y && x1 < r->clip.x + r->clip.w && y1 < r->clip.y + r->clip.h;
        if (in) t.px[y1 * t.pitch + x1] = c;
        if (x1 == x2 && y1 == y2) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x1 += sx; }
        if (e2 <= dx) { err += dx; y1 += sy; }
    }
    return 0;
}

/* An indexed texture's palette with its colour mod applied, kept until the mod changes (a font drawn in one colour
 * after another recomputes its few entries, not a divide a pixel). NULL: out of memory, take the general path. */
const Uint32 *kestrel_mod_palette(SDL_Texture *t)
{
    if (t->mr == 255 && t->mg == 255 && t->mb == 255) return t->pal;
    if (!t->mpal) { t->mpal = malloc(256 * 4); if (!t->mpal) return NULL; t->pmr = ~t->mr; }
    if (t->pmr != t->mr || t->pmg != t->mg || t->pmb != t->mb) {
        for (int i = 0; i < t->npal; i++) {
            Uint32 p = t->pal[i];
            t->mpal[i] = (p & 0xFF000000u) | ((p >> 16 & 255) * t->mr / 255) << 16 | ((p >> 8 & 255) * t->mg / 255) << 8 | (p & 255) * t->mb / 255;
        }
        t->pmr = t->mr; t->pmg = t->mg; t->pmb = t->mb;
    }
    return t->mpal;
}

/* The common case, an indexed texture (all theme art) with the source inside it, scaled or not (klystron's bevels
 * stretch small tiles): per pixel one palette read and, unless the colour is fully opaque or transparent, the
 * blend. The same pixels as the general path below, without its per-pixel bounds tests and colour-mod divides. */
static int copy_indexed(SDL_Texture *tex, tgt_t t, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    int tx0 = (int)(((Uint32)ox * stepx) >> 16) + s->x, tx1 = (int)(((Uint32)(ox + c->w - 1) * stepx) >> 16) + s->x;
    int ty0 = (int)(((Uint32)oy * stepy) >> 16) + s->y, ty1 = (int)(((Uint32)(oy + c->h - 1) * stepy) >> 16) + s->y;
    if (tx0 < 0 || ty0 < 0 || tx1 >= tex->w || ty1 >= tex->h) return 0;
    const Uint32 *pal = kestrel_mod_palette(tex);
    if (!pal) return 0;
    SDL_BlendMode m = tex->blend;
    for (int y = 0; y < c->h; y++) {
        int ty = (int)(((Uint32)(oy + y) * stepy) >> 16) + s->y;
        const Uint8 *ip = tex->idx + ty * tex->w + s->x;
        Uint32 *dp = t.px + (c->y + y) * t.pitch + c->x;
        Uint32 fx = (Uint32)ox * stepx;
        if (stepx == 0x10000u && (m == SDL_BLENDMODE_NONE || m == SDL_BLENDMODE_BLEND)) {   /* unscaled: most UI art */
            const Uint8 *sp = ip + ox;
            if (m == SDL_BLENDMODE_NONE) for (int x = 0; x < c->w; x++) dp[x] = pal[sp[x]] | 0xFF000000u;
            else for (int x = 0; x < c->w; x++) {
                Uint32 p = pal[sp[x]];
                unsigned a = p >> 24;
                if (a == 255) dp[x] = p;
                else if (a) dp[x] = kestrel_blend_px(dp[x], p, a, m);
            }
            continue;
        }
        for (int x = 0; x < c->w; x++, fx += stepx) {
            Uint32 p = pal[ip[fx >> 16]];
            unsigned a = p >> 24;
            if (m == SDL_BLENDMODE_NONE || (a == 255 && m == SDL_BLENDMODE_BLEND)) dp[x] = p | 0xFF000000u;
            else if (a) dp[x] = kestrel_blend_px(dp[x], p, a, m);
        }
    }
    return 1;
}

int SDL_RenderCopy(SDL_Renderer *r, SDL_Texture *tex, const SDL_Rect *sr, const SDL_Rect *dr)
{
    if (!tex) return -1;
    tgt_t t = target_of(r);
    SDL_Rect s = sr ? *sr : (SDL_Rect){ 0, 0, tex->w, tex->h };
    SDL_Rect d = dr ? (SDL_Rect){ dr->x + r->vx, dr->y + r->vy, dr->w, dr->h } : (SDL_Rect){ r->vx, r->vy, t.w, t.h };
    if (s.w <= 0 || s.h <= 0 || d.w <= 0 || d.h <= 0) return 0;
    /* source step in 16.16 per destination pixel; clipping moves the destination, the source follows */
    Uint32 stepx = s.w == d.w ? 0x10000u : ((Uint32)s.w << 16) / (Uint32)d.w;   /* unscaled (each glyph): no divide */
    Uint32 stepy = s.h == d.h ? 0x10000u : ((Uint32)s.h << 16) / (Uint32)d.h;
    SDL_Rect c = d;
    int ox = 0, oy = 0;
    if (!kestrel_clip_rect(&c, &ox, &oy, t.w, t.h, r->clip_on ? &r->clip : NULL)) return 0;
    if (!t.px) { kestrel_defer_copy(tex, &c, &s, ox, oy, stepx, stepy); return 0; }
    if (tex->idx && copy_indexed(tex, t, &c, &s, ox, oy, stepx, stepy)) return 0;
    int mod = tex->mr != 255 || tex->mg != 255 || tex->mb != 255;
    for (int y = 0; y < c.h; y++) {
        int ty = (int)(((Uint32)(oy + y) * stepy) >> 16) + s.y;
        if (ty < 0 || ty >= tex->h) continue;
        const Uint32 *sp = tex->px ? tex->px + ty * tex->w : NULL;
        const Uint8 *ip = tex->idx ? tex->idx + ty * tex->w : NULL;
        Uint32 *dp = t.px + (c.y + y) * t.pitch + c.x;
        Uint32 fx = (Uint32)ox * stepx;
        for (int x = 0; x < c.w; x++, fx += stepx) {
            int tx = (int)(fx >> 16) + s.x;
            if (tx < 0 || tx >= tex->w) continue;
            Uint32 p = sp ? sp[tx] : tex->pal[ip[tx]];
            unsigned a = p >> 24;
            if (tex->blend != SDL_BLENDMODE_NONE && a == 0) continue;
            if (mod) p = (p & 0xFF000000u) | ((p >> 16 & 255) * tex->mr / 255) << 16 | ((p >> 8 & 255) * tex->mg / 255) << 8 | (p & 255) * tex->mb / 255;
            dp[x] = tex->blend == SDL_BLENDMODE_NONE ? p | 0xFF000000u : kestrel_blend_px(dp[x], p, a, tex->blend);
        }
    }
    return 0;
}

void SDL_RenderPresent(SDL_Renderer *r)
{
    if (r->surface || r->target) return;    /* software / texture targets have nothing to show */
    kestrel_defer_present();
    kestrel_plane_present8(r->fb8, r->fw, r->fh);
    if (kestrel_present_hook) kestrel_present_hook();
}

/* --- cursors: kept as ARGB with the key made transparent; kestrel_plane.c draws the current one --- */
struct SDL_Cursor { int w, h, hx, hy; Uint32 *px; };
static SDL_Cursor *current_cursor;
static int cursor_shown = 1;

SDL_Cursor *SDL_CreateColorCursor(SDL_Surface *s, int hx, int hy)
{
    SDL_Cursor *c = calloc(1, sizeof *c);
    if (!c || !s) return c;
    c->px = malloc((size_t)s->w * (size_t)s->h * 4);
    if (!c->px) return c;
    c->w = s->w; c->h = s->h; c->hx = hx; c->hy = hy;
    for (int y = 0; y < s->h; y++) for (int x = 0; x < s->w; x++) c->px[y * c->w + x] = surf_value(s, x, y);
    return c;
}
/* The system cursor is the host's: an empty cursor here (the plane draws nothing for it). */
SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id) { (void)id; return calloc(1, sizeof(SDL_Cursor)); }
SDL_Cursor *SDL_GetDefaultCursor(void) { static SDL_Cursor none; return &none; }
void SDL_SetCursor(SDL_Cursor *c) { if (c) current_cursor = c; }
void SDL_FreeCursor(SDL_Cursor *c)
{
    if (!c || c == SDL_GetDefaultCursor()) return;
    if (current_cursor == c) current_cursor = NULL;
    free(c->px);
    free(c);
}
int SDL_ShowCursor(int toggle) { if (toggle >= 0) cursor_shown = toggle; return cursor_shown; }

/* For kestrel_plane.c: the cursor to draw now (NULL: none). */
const Uint32 *kestrel_cursor_image(int *w, int *h, int *hx, int *hy)
{
    SDL_Cursor *c = current_cursor;
    if (!cursor_shown || !c || !c->px) return NULL;
    *w = c->w; *h = c->h; *hx = c->hx; *hy = c->hy;
    return c->px;
}
