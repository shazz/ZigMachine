/* Force-included into every pt2 source (-include): the KESTREL port's hooks. */
#ifndef KESTREL_PORT_H
#define KESTREL_PORT_H
#include <stdint.h>
/* A screen bitmap decoded on demand into the one lazy slot (the previous one is freed). */
uint32_t *kestrel_bmp(uint32_t **slot, const uint8_t *packed, uint32_t len);
#define KBMP(n) kestrel_bmp(&n##BMP, n##PackedBMP, sizeof (n##PackedBMP))
/* pt2 is about to draw into this rectangle of video.frameBuffer (clipped to the screen here): the present
 * converts only the rectangles marked since the last one (kestrel_sdl.c). Every frameBuffer write site calls
 * it (patches/pt2_{textout,visuals,sampler,scopes,sampling}.c.sed). */
void kestrel_fb_dirty(int32_t x, int32_t y, int32_t w, int32_t h);
/* "REALLY QUIT ?" without askBox(), whose modal loop never returns on a cart that cannot block: the first
 * press says "PRESS AGAIN: QUIT" on the status line, a second within 3 s confirms (pt2_main.c, split_main.py;
 * patches/pt2_{keyboard,mouse}.c.sed). Quitting goes back to the GEM desktop (kestrel_sdl2's kestrel_quit). */
int kestrel_confirm_quit(void);
void kestrel_quit(void);
#endif
