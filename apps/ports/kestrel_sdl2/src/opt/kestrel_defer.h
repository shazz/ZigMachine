/* kestrel_defer.c's command list, shared with kestrel_defer_draw.c (which draws and replays it). */
#ifndef KESTREL_DEFER_H
#define KESTREL_DEFER_H
#include "kestrel_render_priv.h"

#define TW 16
#define TH 8
#define COLS (400 / TW)
#define ROWS ((280 + TH - 1) / TH)
enum { C_COPY, C_FILL, C_CLEAR, C_LINE };

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

void kestrel_defer_draw(const cmd_t *k, const SDL_Rect *r, Uint8 *fb, int fw, int fh);
void kestrel_defer_replay(const cmd_t *cmds, unsigned n, const Uint32 *dirty, Uint8 *fb, int fw, int fh);
#endif
