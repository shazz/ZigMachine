/* The renderer's window target drawn as 8-bit palette indices (kestrel_palette.c) instead of ARGB: what the plane
 * shows anyway, a quarter of the memory (77 KB for 320x240, not 300), and a texture copy is one table read a pixel
 * (texture index -> window index, cached per texture and colour mod) with no colour conversion left for the
 * present. Every pixel is the colour the ARGB renderer (kestrel_render.c) would have drawn: an opaque or
 * transparent texel is a straight index; anything that blends (alpha between 0 and 255, ADD, MOD) reads the
 * destination's colour from the palette, blends it exactly as before and looks the result up. */
#include "kestrel_render_priv.h"

#define SKIP 0x100u                     /* gmap: transparent, leave the pixel */
#define PART 0x200u                     /* gmap: blends with the pixel under it */

/* ARGB -> index with the last colour remembered (fills and slow paths repeat colours; a compaction renumbers). */
static Uint8 index_of(Uint32 c)
{
    static Uint32 last_c = 0xFF000000u; static Uint8 last_i; static unsigned last_gen;
    c |= 0xFF000000u;
    if (c == last_c && last_gen == kestrel_pal_gen) return last_i;
    Uint8 i = kestrel_colour_index(c);
    last_c = c; last_i = i; last_gen = kestrel_pal_gen;
    return i;
}

static Uint8 blend8(Uint8 d, Uint32 p, unsigned a, SDL_BlendMode m)
{
    return index_of(kestrel_blend_px(kestrel_pal_rgb[d], p, a, m));
}

void kestrel_w8_clear(Uint8 *fb, int w, int h, Uint32 c) { memset(fb, index_of(c), (size_t)w * (size_t)h); }

void kestrel_w8_fill(Uint8 *fb, int w, const SDL_Rect *d, Uint32 c, unsigned a, SDL_BlendMode m)
{
    int opaque = m == SDL_BLENDMODE_NONE || (m == SDL_BLENDMODE_BLEND && a == 255);
    Uint8 i = opaque ? index_of(c) : 0;
    for (int y = d->y; y < d->y + d->h; y++) {
        Uint8 *p = fb + y * w + d->x;
        if (opaque) memset(p, i, (size_t)d->w);
        else for (int x = 0; x < d->w; x++) p[x] = blend8(p[x], c, a, m);
    }
}

void kestrel_w8_line(Uint8 *fb, int w, int h, const SDL_Rect *clip, int x1, int y1, int x2, int y2, Uint32 c)
{
    Uint8 i = index_of(c);
    int dx = abs(x2 - x1), sx = x1 < x2 ? 1 : -1, dy = -abs(y2 - y1), sy = y1 < y2 ? 1 : -1, err = dx + dy;
    for (;;) {
        int in = x1 >= 0 && y1 >= 0 && x1 < w && y1 < h;
        if (in && clip) in = x1 >= clip->x && y1 >= clip->y && x1 < clip->x + clip->w && y1 < clip->y + clip->h;
        if (in) fb[y1 * w + x1] = i;
        if (x1 == x2 && y1 == y2) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x1 += sx; }
        if (e2 <= dx) { err += dx; y1 += sy; }
    }
}

/* The texture's (colour-modded) palette as window indices, SKIP or PART; rebuilt when the mod, the blend mode
 * or the palette numbering changes. gall = every entry is a plain index (no test a pixel). NULL: no memory. */
static const Uint16 *window_map(SDL_Texture *t)
{
    Uint32 key = (Uint32)t->mr << 16 | (Uint32)t->mg << 8 | t->mb | (Uint32)t->blend << 24;
    if (t->gmap && t->gkey == key && t->ggen == kestrel_pal_gen) return t->gmap;
    const Uint32 *pal = kestrel_mod_palette(t);
    if (!pal || (!t->gmap && !(t->gmap = malloc(256 * sizeof *t->gmap + 256)))) return NULL;
    Uint8 *map8 = (Uint8 *)(t->gmap + 256);
    do {
        t->ggen = kestrel_pal_gen; t->gall = 1; t->gpart = 0; t->g8 = 1;
        for (int i = 0; i < t->npal; i++) {
            Uint32 p = pal[i];
            unsigned a = p >> 24;
            Uint16 v;
            if (t->blend == SDL_BLENDMODE_NONE || (t->blend == SDL_BLENDMODE_BLEND && a == 255)) v = kestrel_colour_index(p);
            else v = a ? PART : SKIP;
            if (v > 255) t->gall = 0;
            if (v == PART) t->gpart = 1;
            if (v == 255 || v == PART) t->g8 = 0;           /* 255 is the twin's "skip" */
            t->gmap[i] = v; map8[i] = v < 256 ? (Uint8)v : 255;
        }
    } while (t->ggen != kestrel_pal_gen);           /* a compaction while building: the early entries are stale */
    t->gkey = key;
    return t->gmap;
}

/* One row of texels (unscaled: sp[x]; scaled: ip[fx >> 16]) through the map. */
static void row8(Uint8 *dp, const Uint8 *ip, int n, Uint32 fx, Uint32 stepx, SDL_Texture *t, const Uint32 *pal)
{
    const Uint16 *map = t->gmap;
    if (stepx == 0x10000u) {
        const Uint8 *sp = ip + (fx >> 16);
        if (t->gall) { for (int x = 0; x < n; x++) dp[x] = (Uint8)map[sp[x]]; return; }
        if (t->g8) {                                    /* keyed art (glyphs): 255 = transparent */
            const Uint8 *m8 = (const Uint8 *)(map + 256);
            for (int x = 0; x < n; x++) { Uint8 v = m8[sp[x]]; if (v != 255) dp[x] = v; }
            return;
        }
        for (int x = 0; x < n; x++) {
            Uint16 v = map[sp[x]];
            if (v < 256) dp[x] = (Uint8)v;
            else if (v == PART) { dp[x] = blend8(dp[x], pal[sp[x]], pal[sp[x]] >> 24, t->blend); map = window_map(t); }
        }
        return;
    }
    for (int x = 0; x < n; x++, fx += stepx) {
        Uint8 ti = ip[fx >> 16];
        Uint16 v = map[ti];
        if (v < 256) dp[x] = (Uint8)v;
        else if (v == PART) { dp[x] = blend8(dp[x], pal[ti], pal[ti] >> 24, t->blend); map = window_map(t); }
    }
}

/* An indexed texture with the source inside it (kestrel_render.c checked): the window-index map, a row at a time. */
static int copy_indexed8(SDL_Texture *t, Uint8 *fb, int w, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    if (!window_map(t)) return 0;
    const Uint32 *pal = kestrel_mod_palette(t);
    for (int y = 0; y < c->h; y++) {
        int ty = (int)(((Uint32)(oy + y) * stepy) >> 16) + s->y;
        row8(fb + (c->y + y) * w + c->x, t->idx + ty * t->w + s->x, c->w, (Uint32)ox * stepx, stepx, t, pal);
    }
    return 1;
}

/* Anything else (ARGB textures, a source partly outside the texture): kestrel_render.c's general path, per pixel. */
static void copy_general8(SDL_Texture *t, Uint8 *fb, int w, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    int mod = t->mr != 255 || t->mg != 255 || t->mb != 255;
    for (int y = 0; y < c->h; y++) {
        int ty = (int)(((Uint32)(oy + y) * stepy) >> 16) + s->y;
        if (ty < 0 || ty >= t->h) continue;
        Uint8 *dp = fb + (c->y + y) * w + c->x;
        Uint32 fx = (Uint32)ox * stepx;
        for (int x = 0; x < c->w; x++, fx += stepx) {
            int tx = (int)(fx >> 16) + s->x;
            if (tx < 0 || tx >= t->w) continue;
            Uint32 p = t->px ? t->px[ty * t->w + tx] : t->pal[t->idx[ty * t->w + tx]];
            unsigned a = p >> 24;
            if (t->blend != SDL_BLENDMODE_NONE && a == 0) continue;
            if (mod) p = (p & 0xFF000000u) | ((p >> 16 & 255) * t->mr / 255) << 16 | ((p >> 8 & 255) * t->mg / 255) << 8 | (p & 255) * t->mb / 255;
            dp[x] = t->blend == SDL_BLENDMODE_NONE ? index_of(p) : blend8(dp[x], p, a, t->blend);
        }
    }
}

/* 1 when drawing this copy twice leaves what drawing it once does (an indexed texture, the source inside it,
 * no texel that blends): kestrel_defer.c may then skip a tile whose commands did not change. */
int kestrel_w8_idempotent(SDL_Texture *t, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    if (!t->idx) return 0;
    int tx0 = (int)(((Uint32)ox * stepx) >> 16) + s->x, tx1 = (int)(((Uint32)(ox + c->w - 1) * stepx) >> 16) + s->x;
    int ty0 = (int)(((Uint32)oy * stepy) >> 16) + s->y, ty1 = (int)(((Uint32)(oy + c->h - 1) * stepy) >> 16) + s->y;
    if (tx0 < 0 || ty0 < 0 || tx1 >= t->w || ty1 >= t->h) return 0;
    return window_map(t) && !t->gpart;
}

void kestrel_w8_copy(SDL_Texture *t, Uint8 *fb, int w, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    if (t->idx) {
        int tx0 = (int)(((Uint32)ox * stepx) >> 16) + s->x, tx1 = (int)(((Uint32)(ox + c->w - 1) * stepx) >> 16) + s->x;
        int ty0 = (int)(((Uint32)oy * stepy) >> 16) + s->y, ty1 = (int)(((Uint32)(oy + c->h - 1) * stepy) >> 16) + s->y;
        if (tx0 >= 0 && ty0 >= 0 && tx1 < t->w && ty1 < t->h && copy_indexed8(t, fb, w, c, s, ox, oy, stepx, stepy)) return;
    }
    copy_general8(t, fb, w, c, s, ox, oy, stepx, stepy);
}
