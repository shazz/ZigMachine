/* The mouse pointer on the board (bcursor.c). The browser shows the host's own cursor over
 * the canvas, so the machine draws none; the board has no host cursor, so the firmware lays
 * GEM's arrow over the finished picture, for a cart that takes the mouse. */
#ifndef ZM_BCURSOR_H
#define ZM_BCURSOR_H
#include <stdint.h>
/* The glass's REG_POINTER word as binput.c read it: where the arrow goes. */
void bcursor_track(uint32_t ptr);
/* After the planes, before PRESENT: the arrow into the back picture (no-op for a cart
 * without pointer(), or one that draws its own: input_bridge.h input_arrow). The machine's
 * PFB is untouched, so scene_hash never sees it. */
void bcursor_draw(void);
#endif
