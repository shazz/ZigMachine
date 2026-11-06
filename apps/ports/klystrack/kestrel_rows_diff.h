/* kestrel_rows_diff.c: the window tiles a scrolled pattern-rows cache changes (see there). */
#ifndef KESTREL_ROWS_DIFF_H
#define KESTREL_ROWS_DIFF_H
#include <SDL2/SDL.h>

#define KR_ROWS 32                       /* cache rows with hashes (a taller cache compares its pixels) */
#define KR_WORDS 64                      /* 4-pixel words a cache line (256 pixels) */
#define KR_TILES 18                      /* window tile columns those can touch */
typedef struct { Uint32 h[KR_ROWS][KR_TILES]; int ok; } rowhash_t;

int kr_fits(int w, int h);
/* Before the cache (w x h window indices at track) is scrolled by d lines: name the tiles that change. */
void kr_changes(void *renderer, const Uint8 *idx, int w, int h, const SDL_Rect *track, int d, rowhash_t *rh);
/* After rows `rows` were drawn into it (all of them when rh has no hashes yet). */
void kr_hash(const Uint8 *idx, int w, int h, const SDL_Rect *track, Uint64 rows, rowhash_t *rh);
#endif
