/* klystron's VIEWS skipped when nothing they read changed (round 4). klystrack redraws every view of its tab
 * on every repaint (30 a second while a song plays, every pointer move while a menu is open), and nearly all
 * of them draw what they drew the time before. A view (or a block of one, kestrel_pattern.c) runs inside an
 * outer defer group (kestrel_sdl2 kestrel_defer_group.c, two deep: its bevels and strings stay groups inside)
 * whose key is what the view reads:
 *
 *   the caller's words   which view (handler, param, area) and what it reads that moves without an event
 *                        (the timer's second, a slider's parameters)
 *   gen                  bumped by every event that reaches the views (kestrel_view_event) and every SDL timer
 *                        that fired: edits, clicks, keys, the info line's clearing all come that way
 *   the UI state         mused's mode/focus/cursor block, flags, selection (the play and edit position
 *                        only in the keys of the views that show it: kestrel_view_pos)
 *   the draw state       the renderer's clip, the console (colour, cursor, clip, background), the cursor
 *                        and its target, and every texture's colour mod and blend (kestrel_tex_hash)
 *
 * The same key as last frame's group at this point of the window's list, and an event-free repaint: its
 * commands stay, the handler does not run, and the draw state it LEFT is put back (its outputs: clip, console,
 * cursor target, the textures it re-coloured). An event always runs every view (handlers act on it).
 *
 * -DKESTREL_VIEW_CHECK runs every view anyway and logs any that would have been skipped wrongly (its commands
 * or the state it left differ): the proof for a new view or a new input (kestrel_view_check below). */
#include <stdint.h>
#include <string.h>
#include <stddef.h>
#include "kestrel_view.h"
#include "../kestrel_sdl2/src/opt/kestrel_render_priv.h"

int snprintf(char *, unsigned long, const char *, ...);
void kestrel_log(const char *m);

static Uint32 gen;
static unsigned fired;
unsigned kestrel_timers_fired(void);

/* Once a main-loop pass, for each event polled: one the views see (not a bare pointer move, nor a move with a
 * button held while the menu owns the pointer: the views then draw with no event). */
void kestrel_view_event(const SDL_Event *e)
{
    if (e->type == SDL_MOUSEMOTION && (!e->motion.state || mused.mode == MENU)) return;
    gen++;
}

/* For kestrel_bard.c: moves when an event reached the views (only then can the song have been edited). */
Uint32 kestrel_view_gen(void) { return gen; }

static Uint32 mix(Uint32 h, Uint32 v) { h = (h ^ v) * 16777619u; return h ^ h >> 13; }
static Uint32 mixn(Uint32 h, const void *p, size_t n)
{
    const Uint8 *b = p;
    for (size_t i = 0; i + 4 <= n; i += 4) { Uint32 w; memcpy(&w, b + i, 4); h = mix(h, w); }
    return h;
}

/* The play / edit position: it moves on every row while a song plays, and only the views that show it read it
 * (they add kestrel_view_pos to their own key); the rest of the UI state is in every key. */
static const size_t POS[] = { offsetof(Mused, current_patternpos), offsetof(Mused, current_sequencepos),
                              offsetof(Mused, pattern_position), offsetof(Mused, sequence_position) };
unsigned kestrel_view_pos(Uint32 *k)
{
    k[0] = (Uint32)mused.current_patternpos; k[1] = (Uint32)mused.current_sequencepos;
    k[2] = (Uint32)mused.pattern_position; k[3] = (Uint32)mused.sequence_position; k[4] = (Uint32)mused.stat_song_position;
    return 5;
}

/* What every view may read that changes without reaching it as an event. */
static Uint32 ui_state(void)
{
    unsigned f = kestrel_timers_fired();
    if (f != fired) { fired = f; gen++; }
    Uint32 h = mix(2166136261u, gen);
    h = mix(h, mused.flags); h = mix(h, mused.visible_columns);
    int block[(offsetof(Mused, sequence_digit) - offsetof(Mused, octave)) / sizeof(int) + 1];
    memcpy(block, &mused.octave, sizeof block);
    for (unsigned i = 0; i < sizeof POS / sizeof POS[0]; i++) block[(POS[i] - offsetof(Mused, octave)) / sizeof(int)] = 0;
    h = mixn(h, block, sizeof block);
    h = mix(h, (Uint32)mused.current_sequencetrack); h = mix(h, mused.time_signature);
    h = mixn(h, &mused.selection, sizeof mused.selection);
    h = mix(h, mused.mus.cyd ? mused.mus.cyd->flags & CYD_CLIPPING : 0);
    return h;
}
static Uint32 ui_hash(void) { return mix(ui_state(), kestrel_tex_hash); }

/* For kestrel_rows.c: what a channel's cached rows show besides the song and the rows themselves (the views'
 * common key without the draw state, which the rows set as they draw, but with the step numbers' font state). */
Uint32 kestrel_view_common(int ch, const SDL_Rect *r)
{
    Uint32 h = mix(ui_state(), (Uint32)ch);
    h = mix(h, (Uint32)(Uint16)r->x | (Uint32)r->y << 16); h = mix(h, (Uint32)(Uint16)r->w | (Uint32)r->h << 16);
    const GfxSurface *tiny = mused.tinyfont.surface;
    return mix(h, tiny && tiny->texture ? kestrel_tex_word(tiny->texture) : 0);
}

/* The draw state, as words: clip (3), console (7), cursor target (4), cursor (4: set_cursor reads and writes it). */
enum { ST_WORDS = KV_ST_WORDS, TEX_MAX = KV_TEX_MAX, UNRESTORABLE = 0xFFFFu };
int kestrel_window_state(SDL_Renderer *r, Uint32 w[4]);
static void state_get(Uint32 *s)
{
    Uint32 w[4] = { 0 };
    kestrel_window_state(domain->renderer, w);
    s[0] = w[1]; s[1] = w[2]; s[2] = w[3];
    const Console *c = mused.console;
    s[3] = c->current_color; s[4] = c->cursor; s[5] = (Uint32)c->background;
    s[6] = (Uint32)c->clip.x; s[7] = (Uint32)c->clip.y; s[8] = (Uint32)c->clip.w; s[9] = (Uint32)c->clip.h;
    s[10] = (Uint32)mused.cursor_target.x; s[11] = (Uint32)mused.cursor_target.y;
    s[12] = (Uint32)mused.cursor_target.w; s[13] = (Uint32)mused.cursor_target.h;
    s[14] = (Uint32)mused.cursor.x; s[15] = (Uint32)mused.cursor.y; s[16] = (Uint32)mused.cursor.w; s[17] = (Uint32)mused.cursor.h;
}

static void state_set(const Uint32 *s)
{
    SDL_Rect clip = { (Sint16)(Uint16)s[1], (int)s[1] >> 16, (Sint16)(Uint16)s[2], (int)s[2] >> 16 };
    gfx_domain_set_clip(domain, s[0] ? &clip : NULL);
    Console *c = mused.console;
    c->current_color = s[3]; c->cursor = (Uint16)s[4]; c->background = (int)s[5];
    c->clip = (SDL_Rect){ (int)s[6], (int)s[7], (int)s[8], (int)s[9] };
    mused.cursor_target = (SDL_Rect){ (int)s[10], (int)s[11], (int)s[12], (int)s[13] };
    mused.cursor = (SDL_Rect){ (int)s[14], (int)s[15], (int)s[16], (int)s[17] };
}

/* The textures re-coloured since the block began (kestrel_tex_epoch), each at its state now; UNRESTORABLE if
 * more than the outputs hold. */
static void tex_out(Uint32 *o)
{
    if (kestrel_tex_logged > TEX_MAX) { o[0] = UNRESTORABLE; return; }
    for (unsigned i = 0; i < kestrel_tex_logged; i++) {
        SDL_Texture *t = kestrel_tex_log[i];
        if (!t) { o[0] = UNRESTORABLE; return; }
        o[1 + 2 * i] = (Uint32)(uintptr_t)t; o[2 + 2 * i] = kestrel_tex_word(t);
    }
    o[0] = kestrel_tex_logged;
}

static void tex_set(const Uint32 *o)
{
    for (unsigned j = 0; j < o[0]; j++) {
        SDL_Texture *t = (SDL_Texture *)(uintptr_t)o[1 + 2 * j];
        Uint32 w = o[2 + 2 * j];
        SDL_SetTextureColorMod(t, (Uint8)w, (Uint8)(w >> 8), (Uint8)(w >> 16));
        SDL_SetTextureBlendMode(t, (SDL_BlendMode)(w >> 24));
    }
}

int kestrel_view_begin(kv_t *v, const Uint32 *vkey, unsigned n, int may_hit)
{
    if (n > KV_KEY_MAX) n = KV_KEY_MAX;
    memcpy(v->key, vkey, n * 4);
    v->key[n] = ui_hash();
    state_get(v->key + n + 1);
    v->nkey = n + 1 + ST_WORDS;
    Uint32 out[KV_OUT_WORDS];
#ifdef KESTREL_VIEW_CHECK
    v->checking = kestrel_group_begin_ex(domain->renderer, v->key, v->nkey, out, KV_OUT_WORDS, !may_hit);
    if (v->checking && v->nocheck) { state_set(out); tex_set(out + ST_WORDS); return 1; }
    if (v->checking) { memcpy(v->out_was, out, sizeof out); kestrel_group_redo(domain->renderer, v->key, v->nkey, out, KV_OUT_WORDS); }
    v->stored_at = kd_stats.stored;
    kestrel_tex_epoch();
    return 0;
#endif
    if (kestrel_group_begin_ex(domain->renderer, v->key, v->nkey, out, KV_OUT_WORDS, !may_hit)) {
        if (out[ST_WORDS] != UNRESTORABLE) { state_set(out); tex_set(out + ST_WORDS); return 1; }
        kestrel_group_redo(domain->renderer, v->key, v->nkey, out, KV_OUT_WORDS);
    }
    kestrel_tex_epoch();
    return 0;
}

void kestrel_view_end(kv_t *v)
{
    Uint32 out[KV_OUT_WORDS] = { 0 };
    state_get(out);
    tex_out(out + ST_WORDS);
#ifdef KESTREL_VIEW_CHECK
    if (v->checking && (kd_stats.stored != v->stored_at || memcmp(out, v->out_was, sizeof out))) {
        char b[96];
        snprintf(b, sizeof b, "kestrel_view: CHECK view %08x would have been skipped wrongly (stored %u, state %s)",
                 (unsigned)v->key[0], kd_stats.stored - v->stored_at, memcmp(out, v->out_was, sizeof out) ? "differs" : "same");
        kestrel_log(b);
    }
#endif
    kestrel_group_end(out, KV_OUT_WORDS);
}
