/* The pattern view's rows SCROLLED instead of redrawn (round 4). On a row change (every other repaint at the
 * board's speed while a song plays) upstream draws every visible row of every channel again, ~400 strings; but
 * a row's text depends only on the song and the row, not on where the view is scrolled, except the centre row
 * (drawn in the "selected" colour over the selected-row bevel). So each channel keeps a CACHE of its text area
 * (the track's inside) as window pixels, rows in their normal colours over the background:
 *
 *   pass 0  into the cache (kestrel_defer_redirect): the cache scrolled by the rows the view moved (a memmove),
 *           and only the rows it does not hold yet drawn (cleared first) — one row on a row change
 *   then    the cache copied into the window: one command (a raw8 texture, window indices as they are)
 *   pass 1  into the window as upstream, clipped to the selected-row strip S: the background, the bevel and the
 *           rows that cross S (the centre one selected) — exactly upstream's draws there, in its order
 *
 * pattern.c's row loop runs once a pass (patches/pattern.c.sed), skipping the rows a pass does not want. A
 * cache is drawn whole again when anything else it shows may have changed (the song, the theme, the column
 * layout: the views' common key, kestrel_view_common). On an event (a click reaches the rows as they draw and
 * may move the view under them), or when the heap has no room for a cache, the rows draw into the window in
 * upstream's one pass, and the cache is drawn whole the next time. */
#include <string.h>
#include "kestrel_view.h"
#include "theme.h"
#include "mybevdefs.h"
#include "gui/bevel.h"
#include "gui/view.h"
#include "../kestrel_sdl2/src/opt/kestrel_render_priv.h"
#include "kestrel_rows_diff.h"

size_t kestrel_heap_largest(void);   /* kestrel_sdl2/src/kestrel_heap.c */

enum { CACHES = (KPAL_SLOTS - KPAL_CACHE) / 2, H = 8, MAXROWS = 64 };
typedef struct { SDL_Texture tex; Uint32 key; int top, valid, whole; unsigned gen; } cache_t;
void kestrel_window_dirty(void *renderer, const SDL_Rect *d);   /* kestrel_sdl2's kestrel_render.c */
static cache_t caches[CACHES], strips[CACHES];
static rowhash_t hashes[CACHES];                        /* a row cache's row hashes (kestrel_rows_diff.c) */
#define RH(c) (&hashes[(c) - caches])
enum { PLAIN, CACHE, STRIP, WINDOW };   /* the pass: upstream's one, into the cache, into the strip, on the window */
static struct { cache_t *c, *st; SDL_Rect s; int mode, top, selected; Uint64 want; } p;

/* The texture *c for a w x h picture of window indices (palette slot `slot`): NULL if the heap has no room. */
static cache_t *sized(cache_t *c, int slot, int w, int h)
{
    if (w <= 0 || h <= 0) return NULL;
    if (c->tex.w != w || c->tex.h != h || !c->tex.idx) {
        unsigned serial = c->tex.serial;      /* a new picture at the same address: never last frame's serial */
        free(c->tex.idx);
        memset(c, 0, sizeof *c);
        c->tex.serial = serial + 1;
        kestrel_palette_track(slot, NULL, 0);
        /* only from room to spare: a failed malloc would make the heap let the window's draw list go */
        size_t need = (size_t)w * (size_t)h;
        if (kestrel_heap_largest() < need + 64 * 1024 || !(c->tex.idx = malloc(need))) return NULL;
        c->tex.w = w; c->tex.h = h; c->tex.raw8 = 1; c->tex.mr = c->tex.mg = c->tex.mb = 255;
        c->tex.blend = SDL_BLENDMODE_NONE; c->tex.access = SDL_TEXTUREACCESS_STATIC;
        kestrel_palette_track(slot, c->tex.idx, (unsigned)(w * h));
    }
    return c;
}

/* Rows top..top+MAXROWS whose strip in the cache is not all inside lines [v0, v1): those to draw. */
static Uint64 rows_outside(int v0, int v1, int h)
{
    Uint64 m = 0;
    for (int i = 0; i < MAXROWS && i * H < h; i++) {
        int y0 = i * H, y1 = y0 + H < h ? y0 + H : h;
        if (y0 < v0 || y1 > v1) m |= (Uint64)1 << i;
    }
    return m;
}

/* The cache moved to `top`: what it holds scrolled with it; returns the rows it does not hold. c->whole: its
 * picture must go to the window whole (a new serial), else the tiles that change are named here. */
static Uint64 scroll(GfxDomain *dom, cache_t *c, const SDL_Rect *track, int top, Uint32 key)
{
    int w = c->tex.w, h = c->tex.h, d = (top - c->top) * H;
    c->whole = !c->valid || c->key != key || d >= h || -d >= h || c->gen != kestrel_pal_gen || w % 4 || w / 4 > KR_WORDS;
    if (c->whole) { RH(c)->ok = 0; return rows_outside(0, 0, h); }
    if (d) kr_changes(dom->renderer, c->tex.idx, w, h, track, d, RH(c));   /* the tiles that change: named */
    if (d > 0) memmove(c->tex.idx, c->tex.idx + d * w, (size_t)((h - d) * w));
    if (d < 0) memmove(c->tex.idx - d * w, c->tex.idx, (size_t)((h + d) * w));
    return d >= 0 ? rows_outside(0, h - d, h) : rows_outside(-d, h, h);
}

static void clip_and_rect(GfxDomain *dom, SDL_Rect *r, Uint32 rgb) { gfx_domain_set_clip(dom, r); gfx_rect(dom, r, rgb); }

/* A cache's picture into the window at r: one command (changed: its serial moved on, not last frame's picture). */
static void put(GfxDomain *dom, cache_t *c, const SDL_Rect *r, int changed)
{
    kestrel_defer_redirect(NULL, 0, 0, 0, 0);
    if (changed) c->tex.serial++;
    gfx_domain_set_clip(dom, NULL);
    SDL_RenderCopy(dom->renderer, &c->tex, &(SDL_Rect){ 0, 0, r->w, r->h }, r);
}

/* Pass 0: the cache scrolled to `top`, the rows it lacks cleared and wanted (drawn into it, normal colours). */
static int cache_pass(GfxDomain *dom, int ch, const SDL_Rect *track)
{
    p.want = scroll(dom, p.c, track, p.top, kestrel_view_common(ch, track));
    p.mode = CACHE;
    kestrel_defer_redirect(p.c->tex.idx, track->w, track->h, track->x, track->y);
    for (int i = 0; i < MAXROWS; i++)
        if (p.want >> i & 1) {
            SDL_Rect s = { track->x, track->y + i * H, track->w, H };
            clip_rect(&s, track);
            if (s.h <= 0) continue;
            if (!p.c->whole) kestrel_window_dirty(dom->renderer, &s);   /* a new row: drawn again there */
            clip_and_rect(dom, &s, colors[COLOR_BACKGROUND]);
        }
    return 1;
}

/* Pass 1: the cache into the window, then the selected-row strip S as upstream draws it there (background,
 * bevel, the rows crossing it, the centre one selected): into a strip cache copied after it, or on the window
 * itself when a play-position bevel (no follow-play) is drawn over the rows too. */
static int strip_pass(GfxDomain *dom, int ch, const SDL_Rect *track, const SDL_Rect *row)
{
    kr_hash(p.c->tex.idx, p.c->tex.w, p.c->tex.h, track, p.want, RH(p.c));   /* the rows just drawn */
    put(dom, p.c, track, p.c->whole);
    p.c->gen = kestrel_pal_gen;
    p.c->key = kestrel_view_common(ch, track); p.c->top = p.top; p.c->valid = 1;
    p.s = (SDL_Rect){ track->x, row->y, track->w, row->h };   /* the bevel's lines, the whole track wide (text runs past it) */
    clip_rect(&p.s, track);
    if (p.s.h <= 0 || p.s.w <= 0) return 0;
    int playpos = (mused.flags & SONG_PLAYING) && !(mused.flags & FOLLOW_PLAY_POSITION);
    p.st = playpos ? NULL : sized(&strips[ch], KPAL_CACHE + CACHES + ch, p.s.w, p.s.h);
    p.mode = p.st ? STRIP : WINDOW;
    if (p.st) kestrel_defer_redirect(p.st->tex.idx, p.s.w, p.s.h, p.s.x, p.s.y);
    clip_and_rect(dom, &p.s, colors[COLOR_BACKGROUND]);
    bevelex(dom, row, mused.slider_bevel, BEV_SELECTED_PATTERN_ROW, BEV_F_STRETCH_ALL);
    int first = (p.s.y - track->y) / H, last = (p.s.y + p.s.h - 1 - track->y) / H;
    p.want = 0;
    for (int i = first; i <= last && i < MAXROWS; i++) if (i >= 0) p.want |= (Uint64)1 << i;
    p.selected = mused.pattern_position;
    return 1;
}

/* Pass `pass` of channel ch's rows (track: its inside, row: the selected-row bevel); 0 when the passes are done. */
int kestrel_rows_pass(int pass, GfxDomain *dom, int ch, const SDL_Rect *track, int top, const SDL_Rect *row, const SDL_Event *ev)
{
    if (pass == 0) {
        p = (__typeof__(p)){ ch >= 0 && ch < CACHES ? sized(&caches[ch], KPAL_CACHE + ch, track->w, track->h) : NULL,
                             NULL, { 0 }, PLAIN, top, -0x7FFFFFFF, ~(Uint64)0 };
        if (p.c && !kestrel_view_quiet(ev)) { p.c->valid = 0; p.c = NULL; }   /* an event: it may move the view */
        if (!p.c) { p.selected = mused.pattern_position; return 1; }       /* upstream's one pass */
        return cache_pass(dom, ch, track);
    }
    if (p.mode == CACHE) return strip_pass(dom, ch, track, row);
    if (p.mode == STRIP) put(dom, p.st, &p.s, 1);
    p.mode = PLAIN;
    return 0;
}

int kestrel_rows_wanted(int r) { int i = r - p.top; return i >= 0 && i < MAXROWS && (p.want >> i & 1); }
int kestrel_rows_selected(void) { return p.selected; }
int kestrel_rows_events(void) { return p.mode == PLAIN; }
int kestrel_rows_on_window(void) { return p.mode == PLAIN || p.mode == WINDOW; }

/* pattern.c's clip to a pattern's rows: in pass 1, inside the strip S as well. */
void kestrel_rows_clip(GfxDomain *dom, const SDL_Rect *pat)
{
    SDL_Rect c = *pat;
    if (p.mode == STRIP || p.mode == WINDOW) clip_rect(&c, &p.s);
    gfx_domain_set_clip(dom, &c);
}
