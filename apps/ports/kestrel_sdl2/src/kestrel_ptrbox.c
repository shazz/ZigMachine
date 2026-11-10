/* Tell the host where the program's picture is (env.hostPointerBox, docs/HW_API.md "The pointer's
 * box"), so the board's mouse stops at its edge: a port draws a smaller picture centred in a 400x280
 * plane (pt2-clone 320x255, klystrack 320x240) and its cursor is drawn only over that picture, so
 * a pointer allowed over the whole plane vanished past it (Matt, 9 Nov). The browser ignores it.
 *
 *   kestrel_ptrbox_plane(full, px, py, w, h)  the w x h picture at (px, py) of plane 0, a FULLSCREEN
 *                                             400x280 plane (full) or a normal 320x200 one; sent only
 *                                             when it changed */
#include <SDL2/SDL.h>

__attribute__((import_module("env"), import_name("hostPointerBox"))) extern void hostPointerBox(int x0, int y0, int x1, int y1);

static int sent[4], have;

void kestrel_ptrbox_plane(int full, int px, int py, int w, int h)
{
    /* pointer() coordinates: the visible window's origin, x in medium-res pixels (a low-res pixel is
     * two); a FULLSCREEN plane's (0, 0) is the raster's, 40 low-res pixels left of and 40 rows above it. */
    int x0 = 2 * px - (full ? 80 : 0), y0 = py - (full ? 40 : 0);
    int b[4] = {x0, y0, x0 + 2 * w, y0 + h};
    if (have && b[0] == sent[0] && b[1] == sent[1] && b[2] == sent[2] && b[3] == sent[3]) return;
    have = 1;
    for (int i = 0; i < 4; i++) sent[i] = b[i];
    hostPointerBox(b[0], b[1], b[2], b[3]);
}
