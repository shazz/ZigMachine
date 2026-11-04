/* Draws the recorded window commands (kestrel_defer.c): one in full, or all of them clipped to the runs of
 * dirty tiles of each 8-line band. A copy draws with its recorded colour mod and blend, put back after. */
#include "kestrel_defer.h"

/* One command, clipped to r (NULL: everything). The texture's mod and blend are the recorded ones. */
void kestrel_defer_draw(const cmd_t *k, const SDL_Rect *r, Uint8 *fb, int fw, int fh)
{
    if (OP(k) >= C_GROUP) return;                           /* a group's GROUP / KEY / OUT: no pixels */
    SDL_Rect c = RECT(k->c), s = RECT(k->s);
    SDL_BlendMode m = (SDL_BlendMode)(k->kind >> 4 & 7);
    if (OP(k) == C_LINE) {
        SDL_Rect clip = k->kind >> 7 & 1 ? s : (SDL_Rect){ 0, 0, fw, fh };
        if (r && !kestrel_clip_rect(&clip, NULL, NULL, fw, fh, r)) return;
        kestrel_w8_line(fb, fw, fh, &clip, c.x, c.y, c.w, c.h, k->colour);
        return;
    }
    int ox = LO(k->oxy), oy = HI(k->oxy);
    if (r && !kestrel_clip_rect(&c, &ox, &oy, fw, fh, r)) return;
    if (OP(k) == C_FILL) { kestrel_w8_fill(fb, fw, &c, k->colour, k->kind >> 8 & 255, m); return; }
    if (OP(k) == C_CLEAR) { kestrel_w8_fill(fb, fw, &c, k->colour, 255, SDL_BLENDMODE_NONE); return; }
    SDL_Texture *t = k->tex;
    if (k->stepx == 0x10000u && k->stepy == 0x10000u && kestrel_w8_unscaled(t, fb, fw, &c, s.x + ox, s.y + oy, k->mod, m)) return;
    Uint8 mr = t->mr, mg = t->mg, mb = t->mb; SDL_BlendMode bl = t->blend;
    t->mr = (Uint8)k->mod; t->mg = (Uint8)(k->mod >> 8); t->mb = (Uint8)(k->mod >> 16); t->blend = m;
    kestrel_w8_copy(t, fb, fw, &c, &s, ox, oy, k->stepx, k->stepy);
    t->mr = mr; t->mg = mg; t->mb = mb; t->blend = bl;
}

/* Every command replayed into the runs of dirty tiles of the bands it touches. */
void kestrel_defer_replay(const cmd_t *cmds, unsigned n, const Uint32 *dirty, Uint8 *fb, int fw, int fh)
{
    for (unsigned i = 0; i < n; i++) {
        const cmd_t *k = &cmds[i];
        Uint32 b = k->box;
        if (OP(k) == C_GROUP) {                             /* none of its tiles dirty: skip all its commands */
            Uint32 u = k->stepx, any = 0;
            if (!(u & NONE))
                for (unsigned ty = TY0(u); ty <= TY1(u) && !any; ty++) any = dirty[ty] & ((2u << TX1(u)) - (1u << TX0(u)));
            if (!any) i += b & 0x3FFFFFu;
            continue;
        }
        if (b & NONE) continue;
        Uint32 span = (2u << TX1(b)) - (1u << TX0(b));
        unsigned whole = 1;                                 /* every tile it touches dirty: drawn once, unclipped */
        for (unsigned ty = TY0(b); ty <= TY1(b) && whole; ty++) whole = (dirty[ty] & span) == span;
        if (whole) { kestrel_defer_draw(k, NULL, fb, fw, fh); continue; }
        for (unsigned ty = TY0(b); ty <= TY1(b); ty++) {
            Uint32 m = dirty[ty] & span;
            while (m) {
                int x0 = __builtin_ctz(m), x1 = x0;
                while (m >> (x1 + 1) & 1) x1++;
                m &= ~((2u << x1) - (1u << x0));
                SDL_Rect r = { x0 * TW, ty * TH, (x1 - x0 + 1) * TW, TH };
                kestrel_defer_draw(k, &r, fb, fw, fh);
            }
        }
    }
}

