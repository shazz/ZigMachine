/* Soft-float accounting (the `float` build only, -DZM_FCOUNT): every call into
 * libgcc's soft-float routines and libm's rounding/sqrt is wrapped
 * (ld --wrap, list in fcount.wrap), counted per class, and timed. Elsewhere
 * these are no-ops, so the other builds pay nothing. See fcount.c. */
#ifndef ZM_FCOUNT_H
#define ZM_FCOUNT_H

void fcount_clear(void);         /* per-frame counters to zero */
void fcount_calibrate(void);     /* prints "ZM FCAL <probe cycles>" */
void fcount_print_frame(void);   /* appends this frame's CART float fields to a ZM F line */
void fcount_print_totals(void);  /* "ZM FL <op> <owner> <calls> <cycles>" per op used */

#endif
