/* The dirty-line planner's copies (vdirty.c): comparing a fetched row with its
 * copy of the last frame, and bringing the copy up to date.
 *
 * Reading two DDR streams is most of what a comparison costs, and on a row that
 * changed it stops at the first difference: the copy of the rest is queued, and
 * done while the compositor runs a later pass (vseq's spare time), or at the end
 * of the frame. The queue is emptied before any cart code runs again (an HBL
 * handler's layer, or the next frame), so the bytes copied are the ones fetched. */
#ifndef ZM_VDROWS_H
#define ZM_VDROWS_H

#include <stdint.h>

/* copy := src now; whether they differed (the palettes). */
int vdr_cmpcpy(uint8_t* copy, const uint8_t* src, uint32_t n);
/* Whether src differs from copy; if so the copy of the rest is queued. */
int vdr_differ(uint8_t* copy, const uint8_t* src, uint32_t n);
/* Queue copy := src, whole (a row whose copy is not the last frame's). */
void vdr_queue(uint8_t* copy, const uint8_t* src, uint32_t n);
/* Do up to n queued copies, all of them if n < 0; returns how many are left. */
int vdr_copy(int n);

#endif
