/* kestrel_view.c: a block of klystron drawing skipped when nothing it reads changed (see there). */
#ifndef KESTREL_VIEW_H
#define KESTREL_VIEW_H
#include <SDL2/SDL.h>
#include "mused.h"

#define KV_KEY_MAX 24                    /* the caller's words */
#define KV_ST_WORDS 18                   /* the draw state: clip, console, cursor target, cursor */
#define KV_TEX_MAX 8                     /* textures a block may re-colour and still be skipped */
#define KV_OUT_WORDS (KV_ST_WORDS + 1 + 2 * KV_TEX_MAX)
typedef struct {
    Uint32 key[KV_KEY_MAX + 1 + KV_ST_WORDS];
    unsigned nkey;
    int nocheck;                         /* -DKESTREL_VIEW_CHECK leaves it out (set before begin) */
#ifdef KESTREL_VIEW_CHECK
    int checking; unsigned stored_at; Uint32 out_was[KV_OUT_WORDS];
#endif
} kv_t;

/* 1: skipped (its commands kept, the draw state it left put back): do not draw, do not call kestrel_view_end.
 * 0: draw it, then kestrel_view_end(v). may_hit 0: draw it whatever (an event reaches it). */
int kestrel_view_begin(kv_t *v, const Uint32 *vkey, unsigned n, int may_hit);
void kestrel_view_end(kv_t *v);
void kestrel_view_event(const SDL_Event *e);   /* main.c's event loop, each event polled */
unsigned kestrel_view_pos(Uint32 *k);
Uint32 kestrel_view_common(int ch, const SDL_Rect *r);   /* kestrel_rows.c's cache key */          /* the play/edit position, 5 words, for a view that shows it */

/* An event that may change what a view draws or does (anything but no event, or a bare pointer move). */
static inline int kestrel_view_quiet(const SDL_Event *e)
{
    return e->type == 0 || (e->type == SDL_MOUSEMOTION && !e->motion.state);
}

/* kestrel_defer_group.c */
int kestrel_group_begin_ex(void *renderer, const unsigned *key, unsigned n, unsigned *out, unsigned nout, int miss);
int kestrel_group_redo(void *renderer, const unsigned *key, unsigned n, unsigned *out, unsigned nout);
#endif
