/* my_draw_view's handler call (patches/view.c.sed): each view of the tab drawn inside a kestrel_view.c block,
 * skipped on an event-free repaint when nothing it reads changed. Which views may be skipped, and what each
 * reads beyond kestrel_view.c's common key, is listed here; a view not listed always draws (still as a block,
 * so its bevels and strings are reused as before and the list keeps its shape). -DKESTREL_VIEW_CHECK checks
 * every listed view on the scenarios run (kestrel_view.c).
 *
 * pattern_view2 is not a block: it splits itself (kestrel_pattern.c), as its VU meters move on every repaint
 * while a song plays and its rows only on a row change. */
#include "kestrel_view.h"
#include "view.h"
#include "view/pattern.h"
#include "view/sequence.h"
#include "view/timer.h"
#include "view/wavetableview.h"
#include "gui/slider.h"

typedef void (*handler_t)(GfxDomain *, const SDL_Rect *, const SDL_Event *, void *);

/* Views that read nothing but the common key (the song, the UI state, the draw state). */
static const handler_t PLAIN[] = {
    bevel_view, toolbar_view, songinfo1_view, songinfo2_view, songinfo3_view, playstop_view, song_name_view,
    instrument_name_view, instrument_disk_view, fx_name_view, wavetable_name_view,
    instrument_view, instrument_view2, instrument_list,   /* round 5: the instrument tab (its parameters, the list) */
};
/* program_view: the steps each channel playing this instrument's program is at (the cursor it draws there). */
static unsigned prog_ticks(Uint32 *k)
{
    const MusInstrument *inst = &mused.song.instrument[mused.current_instrument];
    Uint32 h = 2166136261u;
    for (int c = 0; c < CYD_MAX_CHANNELS; ++c) {
        int on = mused.channel[c].instrument == inst && (mused.cyd.channel[c].flags & CYD_CHN_ENABLE_GATE)
                 && (mused.channel[c].flags & MUS_CHN_PROGRAM_RUNNING);
        h = (h ^ (on ? 256u + mused.channel[c].program_tick : 0u)) * 16777619u;
    }
    k[0] = h;
    return 1;
}
/* What of the play / edit position a view shows (most of them none): it moves on every row while a song plays. */
static unsigned seq_pos(Uint32 *k)                         /* sequence_view_inner: the selected and play lines */
{
    int steps = mused.sequenceview_steps ? mused.sequenceview_steps : 1;
    k[0] = (Uint32)mused.current_sequencepos; k[1] = (Uint32)mused.sequence_position;
    k[2] = (Uint32)((mused.stat_song_position - mused.sequence_position) * 10 / steps);   /* its play line's y */
    return 3;
}
static unsigned info_pos(Uint32 *k)                        /* info_line: the step under the pattern cursor */
{
    if (mused.focus != EDITPATTERN) return 0;
    const MusPattern *p = get_current_pattern();
    k[0] = p != NULL;
    k[1] = p ? p->step[current_patternstep()].command : 0; k[2] = p ? p->step[current_patternstep()].volume : 0;
    return 3;
}

/* The view's own words: which view, and what it reads that moves without an event. 0: never skipped. */
static unsigned own_key(const View *view, const SDL_Rect *area, Uint32 *k)
{
    unsigned n = 0;
    k[n++] = (Uint32)(uintptr_t)view->handler; k[n++] = (Uint32)(uintptr_t)view->param;
    k[n++] = (Uint32)(Uint16)area->x | (Uint32)area->y << 16; k[n++] = (Uint32)(Uint16)area->w | (Uint32)area->h << 16;
    handler_t h = view->handler;
    for (unsigned i = 0; i < sizeof PLAIN / sizeof PLAIN[0]; i++) if (h == PLAIN[i]) return n;
    if (h == info_line) return n + info_pos(k + n);
    if (h == program_view) return n + prog_ticks(k + n);
    if (h == sequence_view2) return n + seq_pos(k + n);
    if (h == timer_view) {                                  /* the play time, to the second */
        k[n++] = (mused.flags & SONG_PLAYING) ? (Uint32)((mused.play_start_at + mused.time_played) / 1000) : 0;
        return n;
    }
    if (h == sequence_spectrum_view)                        /* the analyzers move every repaint */
        return (mused.flags & SHOW_ANALYZER) && !(mused.flags & SHOW_LOGO) ? 0 : n + seq_pos(k + n);
    if (h == slider) {                                      /* its parameters and the position they point at */
        const SliderParam *p = view->param;
        const Uint32 *w = (const Uint32 *)(const void *)p;
        for (unsigned i = 0; i < sizeof *p / 4 && n < KV_KEY_MAX - 1; i++) k[n++] = w[i];
        k[n++] = p->position ? (Uint32)*p->position : 0;
        return n;
    }
    return 0;
}

void kestrel_view_run(const View *view, GfxDomain *dom, const SDL_Rect *area, const SDL_Event *event, int iter)
{
    if (view->handler == pattern_view2) { view->handler(dom, area, event, view->param); return; }
    Uint32 k[KV_KEY_MAX];
    unsigned n = own_key(view, area, k);
    kv_t v;
    v.nocheck = 0;
    int may = n && !iter && kestrel_view_quiet(event);
    if (kestrel_view_begin(&v, k, n ? n : 4, may)) return;
    view->handler(dom, area, event, view->param);
    kestrel_view_end(&v);
}
