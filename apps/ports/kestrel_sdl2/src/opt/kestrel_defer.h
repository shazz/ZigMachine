/* kestrel_defer.c's command list, shared with kestrel_defer_draw.c (which draws and replays it) and
 * kestrel_defer_group.c. */
#ifndef KESTREL_DEFER_H
#define KESTREL_DEFER_H
#include "kestrel_render_priv.h"

#define TW 16
#define TH 8
#define COLS (400 / TW)
#define ROWS ((280 + TH - 1) / TH)
/* GROUP and NOP draw nothing. A NOP holds the place of a call that drew nothing (clipped away, a space): every
 * call keeps one entry, so a frame whose calls are last frame's keeps every entry at its position. */
enum { C_COPY, C_FILL, C_CLEAR, C_LINE, C_GROUP, C_NOP };

typedef struct {
    Uint32 kind;                        /* op | blend << 4 | has_clip << 7 | alpha << 8: one word (clang merges
                                           neighbouring narrow stores into misaligned wide ones) */
    Uint32 mod, serial;                 /* colour mod r | g << 8 | b << 16; the texture's serial */
    SDL_Texture *tex; Uint32 colour, stepx, stepy;
    Uint32 c[2], s[2];                  /* P2(x, y), P2(w, h). copy: destination, source; fill: c; line: c = ends,
                                           s = clip */
    Uint32 oxy;                         /* P2(ox, oy) */
    /* not compared (derived from the above): */
    Uint32 box;                         /* tiles touched: tx0 | tx1 << 5 | ty0 << 10 | ty1 << 16; NONE; BLENDS */
} __attribute__((aligned(8))) cmd_t;      /* 56 bytes */
#define NONE (1u << 22)
#define BLENDS (1u << 23)
#define OCCB (1u << 24)                 /* may cover whole tiles opaquely: kestrel_defer_draw.c looks only at these */
#define TX0(b) ((b) & 31)
#define TX1(b) ((b) >> 5 & 31)
#define TY0(b) ((b) >> 10 & 63)
#define TY1(b) ((b) >> 16 & 63)
#define OP(k) ((k)->kind & 15)
/* Two 16-bit values a word: word stores, no halfword ones (each costs a store on the board). */
#define P2(a, b) ((Uint32)(Uint16)(a) | (Uint32)(b) << 16)
#define LO(v) ((int)(Sint16)(Uint16)(v))
#define HI(v) ((int)(Sint32)(v) >> 16)
#define R16(d, r) ((d)[0] = P2((r).x, (r).y), (d)[1] = P2((r).w, (r).h))
#define RECT(a) ((SDL_Rect){ LO((a)[0]), HI((a)[0]), LO((a)[1]), HI((a)[1]) })
#define CMD_WORDS (__builtin_offsetof(cmd_t, box) / 4)

/* kestrel_defer.c's list, for kestrel_defer_group.c */
#define KD_ARENA 16384                  /* words of group keys and outputs (kestrel_defer_group.c) */
typedef struct {
    cmd_t *list; unsigned n, nlast, cap;   /* this frame's first n entries; last frame's ran to nlast */
    int deferring, immediate;
    Uint32 *arena; unsigned na; int stale;   /* group keys and outputs, used to na; stale: none matches */
    Uint8 *rbuf; int rw, rh, rx, ry;       /* kestrel_defer_redirect: draws go there at once, not to the list */
    unsigned gopen;                        /* groups open (kestrel_defer_group.c), and their entries' tiles so far: */
    Uint32 gx0[2], gy0[2], gx1[2], gy1[2], gbl[2];   /* kept as entries join, not looked for at the group's end */
    /* The entries marked OCCB, in list order: this frame's as they join (commit, or a reused group's from last
     * frame's list), last frame's for that; so the replay never walks the whole list for them (a D$ miss an
     * entry). More than KD_OCC: the rest are not occluders (only fewer tiles hidden). */
    unsigned occ[2][64], nocc[2], occ_pp;  /* [0] this frame, [1] last frame; occ_pp: [1] read up to there */
} kd_t;
#define KD_OCC 64
extern kd_t kd;
static inline void kd_occ_add(unsigned i) { if (kd.nocc[0] < KD_OCC) kd.occ[0][kd.nocc[0]++] = i; }
/* A reused group's entries lo..hi: last frame's occluders there are this frame's. */
static inline void kd_occ_carry(unsigned lo, unsigned hi)
{
    while (kd.occ_pp < kd.nocc[1] && kd.occ[1][kd.occ_pp] < lo) kd.occ_pp++;
    while (kd.occ_pp < kd.nocc[1] && kd.occ[1][kd.occ_pp] <= hi) kd_occ_add(kd.occ[1][kd.occ_pp++]);
}
/* Entry box b (or a reused inner group's tiles) joins every open group. */
static inline void kd_group_note(Uint32 b)
{
    for (unsigned j = 0; j < kd.gopen; j++) {
        kd.gbl[j] |= b & BLENDS;
        if (b & NONE) continue;
        if (TX0(b) < kd.gx0[j]) kd.gx0[j] = TX0(b);
        if (TY0(b) < kd.gy0[j]) kd.gy0[j] = TY0(b);
        if (TX1(b) > kd.gx1[j]) kd.gx1[j] = TX1(b);
        if (TY1(b) > kd.gy1[j]) kd.gy1[j] = TY1(b);
    }
}
void kd_mark(const cmd_t *k);
int kd_same(const cmd_t *a, const cmd_t *b);
void kd_flush(void);

void kestrel_defer_draw(const cmd_t *k, const SDL_Rect *r, Uint8 *fb, int fw, int fh);
void kestrel_defer_draw_at(const cmd_t *k, Uint8 *buf, int w, int h, int x, int y);
void kestrel_defer_replay(const cmd_t *cmds, unsigned n, const Uint32 *dirty, Uint8 *fb, int fw, int fh);
#endif
