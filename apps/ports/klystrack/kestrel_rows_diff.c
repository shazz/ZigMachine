/* Which window tiles a scrolled pattern-rows cache (kestrel_rows.c) really changes (round 5). The cache keeps
 * its serial across a scroll, so its copy into the window is last frame's command and dirties nothing by
 * itself; the tiles where the picture after the scroll differs from the one before are named here
 * (kestrel_window_dirty). On a row change most rows' "--- -- ---" land on the same text.
 *
 * Each cache row (8 lines) keeps a hash of its pixels per 16-pixel window tile column (rowhash_t), taken when
 * the row is drawn. A scroll by dr rows puts row i + dr's picture at row i: where their hashes differ, row i's
 * tiles change. The hashes scroll with the rows; the rows drawn new are hashed after they are drawn. Without
 * hashes (the first scroll after the cache was drawn whole, a cache taller than KR_ROWS rows) the pixels are
 * compared, word by word. */
#include <string.h>
#include <SDL2/SDL.h>
#include "kestrel_rows_diff.h"

void kestrel_window_dirty(void *renderer, const SDL_Rect *d);   /* kestrel_sdl2's kestrel_render.c */

enum { H = 8, TW = 16 };                    /* a cache row; the window's tile (kestrel_defer.h TW, TH = 8) */

/* Each 4-pixel word's window tile columns (one or two, relative to the track's first). */
static int word_tiles(const SDL_Rect *track, int words, Uint32 *wt)
{
    const int tx0 = track->x / TW;
    for (int x = 0; x < words; x++)
        wt[x] = 1u << ((track->x + 4 * x) / TW - tx0) | 1u << ((track->x + 4 * x + 3) / TW - tx0);
    return tx0;
}

/* The tiles in mask m (relative to tile tx0) of window lines y0..y1, inside the track: drawn again. */
static void mark(void *renderer, const SDL_Rect *track, int tx0, Uint32 m, int y0, int y1)
{
    while (m) {
        int t0 = __builtin_ctz(m), t1 = t0;
        while (t1 < 31 && (m >> (t1 + 1) & 1)) t1++;
        m &= ~((2u << t1) - (1u << t0));
        int x0 = (tx0 + t0) * TW, x1 = (tx0 + t1 + 1) * TW;
        if (x0 < track->x) x0 = track->x;
        if (x1 > track->x + track->w) x1 = track->x + track->w;
        kestrel_window_dirty(renderer, &(SDL_Rect){ x0, y0, x1 - x0, y1 - y0 });
    }
}

/* No hashes: lines y0..y1 of the cache, which will hold line y + d of what it holds now, compared a word at a
 * time, a window band (8 lines) at a time. */
static void compare_pixels(void *renderer, const Uint8 *idx, int w, const SDL_Rect *track, int y0, int y1, int d)
{
    const int words = w / 4;
    Uint32 wt[KR_WORDS];
    int tx0 = word_tiles(track, words, wt);
    for (int y = y0; y < y1;) {
        int band_end = y + (H - (track->y + y) % H);
        if (band_end > y1) band_end = y1;
        Uint32 m = 0;
        for (; y < band_end; y++) {
            const Uint32 *a = (const Uint32 *)(const void *)(idx + y * w), *b = a + d * words;
            for (int x = 0; x < words; x++) if (a[x] != b[x]) m |= wt[x];
        }
        mark(renderer, track, tx0, m, track->y + band_end - 1, track->y + band_end);
    }
}

int kr_fits(int w, int h) { return w % 4 == 0 && w / 4 <= KR_WORDS && (h + H - 1) / H <= KR_ROWS; }

void kr_changes(void *renderer, const Uint8 *idx, int w, int h, const SDL_Rect *track, int d, rowhash_t *rh)
{
    const int rows = (h + H - 1) / H, dr = d / H;
    if (!rh->ok || d % H || !kr_fits(w, h)) {
        rh->ok = 0;
        if (d > 0) compare_pixels(renderer, idx, w, track, 0, h - d, d);
        if (d < 0) compare_pixels(renderer, idx, w, track, -d, h, d);
        return;
    }
    Uint32 wt[KR_WORDS];
    /* the rows kept (kestrel_rows.c rows_outside): scrolled up, the whole ones whose source is whole; scrolled
     * down, every row from -dr (a last partial row takes the top of a whole one: its hash, of the whole row,
     * then differs from any partial row's and equals another only where the whole rows are the same) */
    const int tx0 = word_tiles(track, w / 4, wt), full = h / H;
    for (int i = dr > 0 ? 0 : -dr; i < (dr > 0 ? full - dr : rows); i++) {
        Uint32 m = 0;
        for (int t = 0; t < KR_TILES; t++) if (rh->h[i][t] != rh->h[i + dr][t]) m |= 1u << t;
        mark(renderer, track, tx0, m, track->y + i * H, track->y + (i * H + H < h ? i * H + H : h));
    }
    if (dr > 0) memmove(rh->h[0], rh->h[dr], (size_t)(rows - dr) * sizeof rh->h[0]);
    if (dr < 0) memmove(rh->h[-dr], rh->h[0], (size_t)(rows + dr) * sizeof rh->h[0]);
}

/* Rows `rows` (bit i: row i) of the cache drawn: their hashes taken; all of them when the cache has none. */
void kr_hash(const Uint8 *idx, int w, int h, const SDL_Rect *track, Uint64 rows, rowhash_t *rh)
{
    if (!kr_fits(w, h)) { rh->ok = 0; return; }
    if (!rh->ok) rows = ~(Uint64)0;
    Uint32 wt[KR_WORDS];
    const int words = w / 4;
    word_tiles(track, words, wt);
    for (int i = 0; i * H < h; i++) {
        if (!(rows >> i & 1)) continue;
        Uint32 *hh = rh->h[i];
        for (int t = 0; t < KR_TILES; t++) hh[t] = 2166136261u;
        for (int y = i * H; y < i * H + H && y < h; y++) {
            const Uint32 *a = (const Uint32 *)(const void *)(idx + y * w);
            for (int x = 0; x < words; x++) {
                Uint32 m = wt[x], v = a[x];
                while (m) { int t = __builtin_ctz(m); m &= m - 1; hh[t] = (hh[t] ^ v) * 16777619u; hh[t] ^= hh[t] >> 15; }
            }
        }
    }
    rh->ok = 1;
}
