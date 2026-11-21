/* The VGM engine's bench on BARD (an snd-cbench image, cycles/sound.mk): libs/c/vgm on a tune linked
 * in as vgm_song[] (a C array of the file), straight to VGM_SEEK tenths of a second, then VGM_FRAMES
 * frames of 1/60 s rendered at the engine's rate, each timed ("F n cycles", "FS ... %": its share of
 * BARD's 60 Hz frame). The engine alone: the player's resampler and Paula output are not in it.
 *   make snd-cbench CBENCH_SRC="cycles/sound/svgmbench.c <song.c> $(VGM_SRC)" \
 *       CBENCH_CFLAGS="-DVGM_SEEK=100 -DVGM_FRAMES=6"     then run zm_ddr.init as snd-bench's */
#include <stdio.h>

#include "../../../libs/c/vgm/zm_vgm.h"
#include "scbench.h"

#ifndef VGM_SEEK
#define VGM_SEEK 100
#endif
#ifndef VGM_FRAMES
#define VGM_FRAMES 6
#endif

extern unsigned char vgm_song[];
extern const unsigned int vgm_song_len;

static int16_t g_lr[2 * 512];

int cbench_run(void) {
    uint32_t rc = zm_vgm_load(vgm_song, vgm_song_len, vgm_song_len);
    if (rc) return printf("VGM load %u\n", (unsigned)rc), 3;
    zm_vgm_seek(VGM_SEEK);
    uint32_t rate = zm_vgm_rate(), acc = 0;
    printf("VGM %u bytes, rate %u, seek %u.%u s\n", vgm_song_len, (unsigned)rate, VGM_SEEK / 10, VGM_SEEK % 10);
    for (int f = 0; f < VGM_FRAMES; f++) {
        uint32_t n = rate / 60u; /* a 60 Hz frame's chip samples, the remainder carried */
        acc += rate - n * 60u;
        if (acc >= 60u) acc -= 60u, n++;
        cb_mark_t t0 = cb_mark();
        zm_vgm_render(g_lr, n);
        cb_frame(f, t0, n);
    }
    printf("VGM loops %u\n", (unsigned)zm_vgm_loops());
    return 0;
}
