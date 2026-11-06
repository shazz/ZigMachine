/* The draw state every texture carries between calls (its colour mod and blend mode), summed up for a caller
 * that skips a block of draws when nothing it reads changed (klystrack's views, apps/ports/klystrack/kestrel_view.c):
 *
 *   kestrel_tex_hash   one word for the colour mod and blend of EVERY live texture: an XOR of one term a texture,
 *                      kept up to date as each changes (so equal states give equal words, whatever the order)
 *   kestrel_tex_log    the textures whose state changed since kestrel_tex_epoch() (each once, up to
 *                      KESTREL_TEX_LOG; kestrel_tex_logged counts them all): what a block of draws left
 *                      changed is these textures, each at its state now
 *
 * kestrel_render.c calls kestrel_tex_note() around every change, creation and destruction. */
#include "kestrel_render_priv.h"

Uint32 kestrel_tex_hash;
SDL_Texture *kestrel_tex_log[KESTREL_TEX_LOG];
unsigned kestrel_tex_logged;
static unsigned epoch = 1;

/* A block of draws starts: the log empties (a texture is logged once an epoch). */
void kestrel_tex_epoch(void) { epoch++; kestrel_tex_logged = 0; }

Uint32 kestrel_tex_word(const SDL_Texture *t)
{
    return (Uint32)t->mr | (Uint32)t->mg << 8 | (Uint32)t->mb << 16 | (Uint32)t->blend << 24;
}

static Uint32 term(const SDL_Texture *t)
{
    Uint32 h = (Uint32)(uintptr_t)t * 2654435761u ^ kestrel_tex_word(t) * 2246822519u;
    return h ^ h >> 15;
}

/* Before a change (on = 0: the old state leaves the hash) and after it (on = 1: the new one joins, logged). */
void kestrel_tex_note(SDL_Texture *t, int on)
{
    kestrel_tex_hash ^= term(t);
    if (!on || t->epoch == epoch) return;
    t->epoch = epoch;
    if (kestrel_tex_logged < KESTREL_TEX_LOG) kestrel_tex_log[kestrel_tex_logged] = t;
    kestrel_tex_logged++;
}

/* Destroyed: out of the hash and out of the log (a caller must never read a freed texture's state). */
void kestrel_tex_gone(SDL_Texture *t)
{
    kestrel_tex_hash ^= term(t);
    for (unsigned i = 0; i < KESTREL_TEX_LOG; i++) if (kestrel_tex_log[i] == t) kestrel_tex_log[i] = NULL;
}
