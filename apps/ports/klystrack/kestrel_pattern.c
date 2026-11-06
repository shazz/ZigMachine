/* The pattern view (view/pattern.c, patches/pattern.c.sed) as kestrel_view.c blocks. pattern_view2 draws the
 * step counter, then the rows of every channel (~400 strings), then the cursor and selection; while a song
 * plays it also draws each channel's VU meter, which moves on every repaint, between that channel's rows and
 * the next channel. So:
 *   the step counter       one block (it moves with the pattern position only)
 *   the channels' rows     one block, the VU meters left out: kestrel_vu_note() keeps where each would go
 *   the VU meters          drawn after that block, each in its own channel's track (the next channel's draws
 *                          never touch it: the same pixels as drawn in between)
 *   cursor and selection   drawn as before (cheap; they follow the focus)
 * Between two rows only the VU meters draw; on a row change the rows block draws again. */
#include "kestrel_view.h"

enum { TAG_ROWS = 0x50415431u, TAG_STEPS = 0x53544550u };

static struct { int channel; SDL_Rect track; int row_y, ah; } vu[MUS_MAX_CHANNELS];
static int nvu;

static int block(kv_t *v, Uint32 tag, const SDL_Rect *dest, const SDL_Event *event)
{
    Uint32 k[8] = { tag, (Uint32)(Uint16)dest->x | (Uint32)dest->y << 16, (Uint32)(Uint16)dest->w | (Uint32)dest->h << 16 };
    return kestrel_view_begin(v, k, 3 + kestrel_view_pos(k + 3), kestrel_view_quiet(event));
}

int kestrel_pattern_rows_begin(kv_t *v, const SDL_Rect *dest, const SDL_Event *event)
{
    /* Drawn again it may take another path (the caches, kestrel_rows.c) with other commands for the same pixels:
     * the view check would flag that; hashes.sh is its proof. */
    v->nocheck = 1;
    if (block(v, TAG_ROWS, dest, event)) return 1;
    nvu = 0;                                  /* drawn again: the meters' places are noted again */
    return 0;
}

int kestrel_pattern_steps_begin(kv_t *v, const SDL_Rect *dest, const SDL_Event *event)
{
    v->nocheck = 0;
    return block(v, TAG_STEPS, dest, event);
}

/* Where channel `channel`'s meter goes (upstream's VU block, at the same point of the loop). */
void kestrel_vu_note(int channel, const SDL_Rect *track, int row_y, int ah)
{
    if (nvu < MUS_MAX_CHANNELS) vu[nvu++] = (__typeof__(vu[0])){ channel, *track, row_y, ah };
}

/* upstream's VU block, for each channel noted. */
void kestrel_vu_draw(GfxDomain *dest_surface)
{
#ifdef KESTREL_TEST_NO_VU /* hashes.sh's proof without the meters (their >255-colour gradient maps by palette order) */
    return;
#endif
    if (!(mused.flags & SONG_PLAYING) || (mused.flags & DISABLE_VU_METERS)) return;
    for (int i = 0; i < nvu; i++) {
        const SDL_Rect *track = &vu[i].track;
        gfx_domain_set_clip(dest_surface, track);
        const int w = mused.vu_meter->surface->w;
        const int h = my_min(mused.vu_meter->surface->h, mused.vis.cyd_env[vu[i].channel] * vu[i].ah / MAX_VOLUME);
        SDL_Rect r = { track->x + track->w / 2 - w / 2, vu[i].row_y - h, w, h };
        SDL_Rect sr = { 0, mused.vu_meter->surface->h - h, mused.vu_meter->surface->w, h };
        gfx_blit(mused.vu_meter, &sr, dest_surface, &r);
    }
}
