/* Dirty lines: which raster lines of the picture being built already hold what a
 * full composite would paint, so the sequencer can leave them alone (vplan.c).
 *
 * Every line has an input VERSION, bumped in a frame where anything a full
 * composite of that line reads differs from the frame before; every picture
 * remembers, per line, the version its row was built from. The picture being
 * built was last built two frames ago, so a line may be skipped only when its
 * version has not moved since: its inputs are the same in this frame, the last
 * one and the one that built the row.
 *
 * The inputs, compared against a copy of the last frame's:
 *   - per line: the background (the CLEAR colour, or BACKGROUND after the
 *     global handler); a BEAM line is always new (its write-backs must run);
 *   - per frame: the enabled planes, fill or not, each plane's geometry (mode,
 *     and what the geometry depends on: stride and HSCROLL in fullscreen,
 *     RESOLUTION in medium) and its palette;
 *   - per plane and line: the bytes the line's pass fetches.
 * The lines a plane with an HBL handler covers are always new: its stores land
 * between passes. If it is not the last enabled plane, or what cannot be
 * compared, the whole frame is UNKNOWN (every line new): an overscan plane (its
 * borders open from state carried down the frame, its noise follows FRAME), a
 * fetch outside the cart's memory or longer than a row.
 *
 * Portable C over the cart's linear memory: the board firmware (vplan.c) and the
 * native proof (host/vdirty_main.c) run the same code. */
#ifndef ZM_VDIRTY_H
#define ZM_VDIRTY_H

#include <stdint.h>

#include "zm_memmap.h"

#define VD_LINES ZM_RASTER_HEIGHT

/* One frame's inputs as the sequencer saw them, after cart.frame(). */
typedef struct {
    const uint8_t* mem; /* the cart's linear memory */
    uint32_t mem_size;
    unsigned enabled;    /* bit p: plane p is composited this frame */
    int fill;            /* the clear was one CLEAR: bg[0] is every line's colour */
    const uint32_t* bg;  /* per line: BACKGROUND as its BG pass reads it */
    const uint8_t* beam; /* per line: a BEAM line */
} vd_frame;

typedef struct {
    uint32_t frames, unknown, bumped; /* frames planned, UNKNOWN ones, lines whose version moved */
    uint32_t mask_moved;              /* frames whose planes a handler switched */
} vd_stats;
extern vd_stats vd;

/* Compare this frame's inputs with the last frame's, bump the lines that moved.
 * Returns 1 if an enabled plane has an HBL handler: the caller asks each plane
 * again where video.zig would, and calls vd_mask_moved if an answer differs
 * from fr->enabled (a handler switched a plane; the plan no longer holds). */
int vd_plan(const vd_frame* fr);
void vd_mask_moved(void);
/* Nothing can be compared this frame (a handler plane): every line is new, and
 * neither picture's rows are trusted again until rebuilt. */
void vd_unknown(void);
/* After vd_plan, once per line, in any order, before anything composites it:
 * compare the bytes line y fetches with their copies, then whether the row of
 * picture `pic` (0 = FB0, 1 = FB1, the one being built) is already right (1:
 * skip it). The row is marked built from this frame's inputs: the caller
 * composites every line it does not skip. Line by line so that the board can
 * compare the next line while the compositor runs this one (vseq_decide). */
int vd_line(int pic, uint32_t y);
/* The rows' copies vd_line left queued (vdrows.h): up to n of them, all if n < 0;
 * all of them before any cart code runs again. Returns how many are left. */
int vd_spare(int n);
/* Rows [y0, y0 + n) of picture `pic` were drawn over after the composite. */
void vd_overdrawn(int pic, uint32_t y0, uint32_t n);

#endif
