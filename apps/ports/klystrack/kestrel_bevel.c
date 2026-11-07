/* A bevel's tiles as RUNS (round 6). Upstream's bevelex (klystron gui/bevel.c) draws a bevel cell by cell:
 * the centre in 8x8 copies, each side in 4x8 or 8x4 strips, so a menu of 19 items is ~700 copies and Edit >
 * Pattern (the Edit dropdown, its sub-menu, their separators and the highlight) ~1,350. With the instrument tab
 * behind it that ran the window's command list (4,608) over: every frame drew everything (~40 est Mc, board
 * 5 fps), while every other menu fitted.
 *
 * Where the bevel's art makes the cells identical, one stretched copy draws the same pixels: a centre of one
 * colour, a top or bottom strip whose rows are each one colour (tiled across = stretched across), a left or
 * right strip whose columns are each one colour. That is read from the TEXTURE's own pixels (what is drawn),
 * once per texture content (its serial) and bevel offset; a part that is not uniform keeps upstream's tiles.
 * The parts are drawn in upstream's order (centre, left and right, top and bottom, corners): each pixel gets
 * the same copies in the same order, so the same picture whatever the blend. patches/bevel.c.sed calls this for
 * BEV_F_NORMAL / BEV_F_DISABLE_CENTER bevels; the STRETCH ones are upstream's already. */
#include <string.h>
#include "gui/bevel.h"
#include "gui/bevdefs.h"
#include "gfx/gfx.h"
#include "../kestrel_sdl2/src/opt/kestrel_render_priv.h"

#define BORDER 4
#define HALF (BEV_SIZE / 2)
enum { U_CENTER = 1, U_TOP = 2, U_BOTTOM = 4, U_LEFT = 8, U_RIGHT = 16, U_KNOWN = 128 };
enum { SLOTS = 4, OFFSETS = 64 };

static struct { const SDL_Texture *t; unsigned serial; Uint8 bits[OFFSETS]; } cache[SLOTS];
static unsigned next_slot;

/* Texel (x, y) of t as a value equal for equal colours: its index, or its ARGB. */
static Uint32 texel(const SDL_Texture *t, int x, int y)
{
    return t->idx ? t->idx[y * t->w + x] : t->px[y * t->w + x];
}

/* Whether every row (rows = 1) or every column (rows = 0) of t's x, y, w x h is one value; both = all one. */
static int lines_uniform(const SDL_Texture *t, int x, int y, int w, int h, int rows)
{
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++)
            if (texel(t, x + i, y + j) != texel(t, rows ? x : x + i, rows ? y + j : y)) return 0;
    return 1;
}

static Uint8 uniform_parts(const SDL_Texture *t, int offset)
{
    int x = offset * BEV_SIZE;
    if ((!t->idx && !t->px) || t->raw8 || x + BEV_SIZE > t->w || BEV_SIZE > t->h) return U_KNOWN;
    Uint8 u = U_KNOWN;
    if (lines_uniform(t, x + BORDER, BORDER, HALF, HALF, 1) && lines_uniform(t, x + BORDER, BORDER, HALF, HALF, 0)) u |= U_CENTER;
    if (lines_uniform(t, x + BORDER, 0, HALF, BORDER, 1)) u |= U_TOP;
    if (lines_uniform(t, x + BORDER, BEV_SIZE - BORDER, HALF, BORDER, 1)) u |= U_BOTTOM;
    if (lines_uniform(t, x, BORDER, BORDER, HALF, 0)) u |= U_LEFT;
    if (lines_uniform(t, x + BEV_SIZE - BORDER, BORDER, BORDER, HALF, 0)) u |= U_RIGHT;
    return u;
}

/* The uniform parts of bevel `offset` in texture t (U_* bits), cached per texture content. */
static unsigned uniform(const SDL_Texture *t, int offset)
{
    if (!t || offset < 0 || offset >= OFFSETS) return 0;
    unsigned s = 0;
    while (s < SLOTS && (cache[s].t != t || cache[s].serial != t->serial)) s++;
    if (s == SLOTS) {
        s = next_slot++ % SLOTS;
        cache[s].t = t; cache[s].serial = t->serial;
        memset(cache[s].bits, 0, sizeof cache[s].bits);
    }
    if (!cache[s].bits[offset]) cache[s].bits[offset] = uniform_parts(t, offset);
    return cache[s].bits[offset];
}

static void blit(GfxDomain *screen, GfxSurface *gfx, int sx, int sy, int sw, int sh, int dx, int dy, int dw, int dh)
{
    SDL_Rect src = { sx, sy, sw, sh }, dest = { dx, dy, dw, dh };
    my_BlitSurface(gfx, &src, screen, &dest);
}

static int min_i(int a, int b) { return a < b ? a : b; }

/* Upstream's centre loop, or one copy when the centre is one colour. */
static void centre(GfxDomain *screen, const SDL_Rect *a, GfxSurface *gfx, int o, unsigned u)
{
    int iw = a->w - 2 * BORDER, ih = a->h - 2 * BORDER;
    if (iw <= 0 || ih <= 0) return;
    if (u & U_CENTER) { blit(screen, gfx, BORDER + o, BORDER, min_i(HALF, iw), min_i(HALF, ih), a->x + BORDER, a->y + BORDER, iw, ih); return; }
    for (int y = BORDER; y < a->h - BORDER; y += HALF)
        for (int x = BORDER; x < a->w - BORDER; x += HALF)
            blit(screen, gfx, BORDER + o, BORDER, min_i(HALF, a->w - x - BORDER), min_i(HALF, a->h - y - BORDER),
                 x + a->x, y + a->y, min_i(HALF, a->w - x - BORDER), min_i(HALF, a->h - y - BORDER));
}

/* Upstream's side loops (left and right per row of cells, then top and bottom per column), each side one copy
 * when its lines are uniform: a merged left (top) side before the loop, a merged right (bottom) one after it, so
 * where the two overlap (a bevel under 8 pixels, a separator) each pixel still gets left before right. */
static void sides(GfxDomain *screen, const SDL_Rect *a, GfxSurface *gfx, int o, unsigned u)
{
    const int R = BEV_SIZE - BORDER, ih = a->h - 2 * BORDER, iw = a->w - 2 * BORDER;
    if (ih > 0) {
        if (u & U_LEFT) blit(screen, gfx, o, BORDER, BORDER, min_i(HALF, ih), a->x, a->y + BORDER, BORDER, ih);
        for (int y = BORDER; y < a->h - BORDER && (~u & (U_LEFT | U_RIGHT)); y += HALF) {
            int h = min_i(HALF, a->h - BORDER - y);
            if (!(u & U_LEFT)) blit(screen, gfx, o, BORDER, BORDER, h, a->x, y + a->y, BORDER, h);
            if (!(u & U_RIGHT)) blit(screen, gfx, R + o, BORDER, BORDER, h, a->x + a->w - BORDER, y + a->y, BORDER, h);
        }
        if (u & U_RIGHT) blit(screen, gfx, R + o, BORDER, BORDER, min_i(HALF, ih), a->x + a->w - BORDER, a->y + BORDER, BORDER, ih);
    }
    if (iw > 0) {
        if (u & U_TOP) blit(screen, gfx, BORDER + o, 0, min_i(HALF, iw), BORDER, a->x + BORDER, a->y, iw, BORDER);
        for (int x = BORDER; x < a->w - BORDER && (~u & (U_TOP | U_BOTTOM)); x += HALF) {
            int w = min_i(HALF, a->w - BORDER - x);
            if (!(u & U_TOP)) blit(screen, gfx, BORDER + o, 0, w, BORDER, a->x + x, a->y, w, BORDER);
            if (!(u & U_BOTTOM)) blit(screen, gfx, BORDER + o, R, w, BORDER, x + a->x, a->y + a->h - BORDER, w, BORDER);
        }
        if (u & U_BOTTOM) blit(screen, gfx, BORDER + o, R, min_i(HALF, iw), BORDER, a->x + BORDER, a->y + a->h - BORDER, iw, BORDER);
    }
}

/* bevelex for BEV_F_NORMAL and BEV_F_DISABLE_CENTER. */
void kestrel_bevel_runs(GfxDomain *screen, const SDL_Rect *area, GfxSurface *gfx, int offset, int bevel_flags)
{
    const int o = offset * BEV_SIZE, R = BEV_SIZE - BORDER;
    unsigned u = uniform(gfx->texture, offset);
    if (!(bevel_flags & BEV_F_DISABLE_CENTER)) centre(screen, area, gfx, o, u);
    sides(screen, area, gfx, o, u);
    blit(screen, gfx, o, 0, BORDER, BORDER, area->x, area->y, BORDER, BORDER);
    blit(screen, gfx, R + o, 0, BORDER, BORDER, area->x + area->w - BORDER, area->y, BORDER, BORDER);
    blit(screen, gfx, R + o, R, BORDER, BORDER, area->x + area->w - BORDER, area->y + area->h - BORDER, BORDER, BORDER);
    blit(screen, gfx, o, R, BORDER, BORDER, area->x, area->y + area->h - BORDER, BORDER, BORDER);
}
