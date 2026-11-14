/* Does plane p cover the whole 800x280 raster, or only the 640x200 visible window? video.zig's
 * renderPlane* rule, the one place the firmware keeps it: vseq_plane_lines (the lines a plane's
 * handler runs on) and bptrbox.h (where the pointer may go) both ask it. */
#ifndef ZM_VWHOLE_H
#define ZM_VWHOLE_H

#include <stdint.h>

#include "zm_memmap.h"

static inline int vplane_whole(uint8_t mode, uint16_t stride) {
    if (mode == ZM_FB_MODE_MEDIUM) return stride >= ZM_RASTER_WIDTH;
    if (mode == ZM_FB_MODE_NORMAL || mode > ZM_FB_MODE_TRUECOLOR_FULL) return stride == ZM_STRIDE_FULLSCREEN;
    return mode == ZM_FB_MODE_FULLSCREEN || mode == ZM_FB_MODE_OVERSCAN || mode == ZM_FB_MODE_TRUECOLOR_FULL;
}

#endif
