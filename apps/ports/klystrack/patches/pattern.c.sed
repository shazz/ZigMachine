# KESTREL (round 4): the pattern view as blocks skipped when nothing they read changed (kestrel_pattern.c): the
# channels' rows (their VU meters drawn after them, they move on every repaint while a song plays) and the step
# counter. The cursor and selection after the rows draw as before.
/^#define HEADER_HEIGHT 12$/i\
#include "kestrel_view.h" /* KESTREL */\
int kestrel_pattern_rows_begin(kv_t *v, const SDL_Rect *dest, const SDL_Event *event);\
int kestrel_pattern_steps_begin(kv_t *v, const SDL_Rect *dest, const SDL_Event *event);\
void kestrel_vu_note(int channel, const SDL_Rect *track, int row_y, int ah);\
void kestrel_vu_draw(GfxDomain *dest_surface);\
int kestrel_rows_pass(int pass, GfxDomain *dom, int ch, const SDL_Rect *track, int top, const SDL_Rect *row, const SDL_Event *ev);\
int kestrel_rows_wanted(int r);\
int kestrel_rows_selected(void);\
int kestrel_rows_events(void);\
int kestrel_rows_on_window(void);\
void kestrel_rows_clip(GfxDomain *dom, const SDL_Rect *pat);
s/^\tint x = 0;$/\tkv_t kv; \/* KESTREL: the channels' rows, a block *\/\
\tif (!kestrel_pattern_rows_begin(\&kv, dest, event)) {\
\tint x = 0;/
s/^\t\tif ((mused.flags & SONG_PLAYING) && !(mused.flags & DISABLE_VU_METERS))$/\t\t} \/* KESTREL: the passes *\/\
\t\tkestrel_vu_note(channel, \&track, row.y, dest->h + dest->y - row.y); \/* KESTREL: drawn after the block *\/\
\t\tif (0)/
# ...and each channel's rows in two passes (kestrel_rows.c): the cache scrolled and its new rows drawn, then the
# selected-row strip on the window; each pass draws only the rows it wants, the cache's in their normal colours.
s/^\t\tfor (int i = 0 ; i < mused.song.num_sequences\[channel\] ; ++i, ++sp)$/\t\tfor (int kpass = 0; kestrel_rows_pass(kpass, dest_surface, channel, \&track, top, \&row, event); kpass++) { sp = \&mused.song.sequence[channel][0]; \/* KESTREL *\/\
\t\tfor (int i = 0 ; i < mused.song.num_sequences[channel] ; ++i, ++sp)/
s/^\t\t\tgfx_domain_set_clip(dest_surface, &pat);$/\t\t\tkestrel_rows_clip(dest_surface, \&pat); \/* KESTREL *\//
s/^\t\t\t\tif (sp->position + step >= bottom) break;$/\t\t\t\tif (sp->position + step >= bottom) break;\
\t\t\t\tif (!kestrel_rows_wanted(sp->position + step)) continue; \/* KESTREL *\//
s/sp->position + step != mused.pattern_position/sp->position + step != kestrel_rows_selected()/
s/^\t\t\t\t\tif (sp && event->type == SDL_MOUSEBUTTONDOWN)$/\t\t\t\t\tif (sp \&\& event->type == SDL_MOUSEBUTTONDOWN \&\& kestrel_rows_events()) \/* KESTREL *\//
s/^\t\t\tif ((mused.flags & SONG_PLAYING) && !(mused.flags & FOLLOW_PLAY_POSITION))$/\t\t\tif ((mused.flags \& SONG_PLAYING) \&\& !(mused.flags \& FOLLOW_PLAY_POSITION) \&\& kestrel_rows_on_window()) \/* KESTREL *\//
s/^\tSDL_Rect pat;$/\tkestrel_view_end(\&kv); } \/* KESTREL *\/\
\tkestrel_vu_draw(dest_surface);\
\tSDL_Rect pat;/
s/^static void pattern_view_stepcounter(GfxDomain \*dest_surface, const SDL_Rect \*dest, const SDL_Event \*event)$/static void pattern_view_stepcounter_draw(GfxDomain *dest_surface, const SDL_Rect *dest, const SDL_Event *event)/
/^void pattern_view2(GfxDomain \*dest_surface, const SDL_Rect \*dest, const SDL_Event \*event, void \*param)$/i\
static void pattern_view_stepcounter(GfxDomain *dest_surface, const SDL_Rect *dest, const SDL_Event *event) /* KESTREL: a block */\
{\
	kv_t kv;\
	if (kestrel_pattern_steps_begin(&kv, dest, event)) return;\
	pattern_view_stepcounter_draw(dest_surface, dest, event);\
	kestrel_view_end(&kv);\
}\

