/* The VGM engine's door (zm_vgm.h): the sequencer (vgm_seq.c) over our YM2612 (libs/c/ym2612) and
 * SN76489 (libs/c/sn76489), one instance. Built for machine-audio.wasm (build.zig) and natively
 * (fpga/host/audio_vgm.c). Our own code. */
#include "zm_vgm.h"

#include <string.h>

#include "vgm_seq.h"
#include "zm_inflate.h"

/* The two chips' levels on the mixer (libs/c/vgm/README.md "Levels"): the YM2612's six channels' sum
 * in Q8, one PSG channel's peak. */
#ifndef ZM_VGM_YM_GAIN
#define ZM_VGM_YM_GAIN 512
#endif
#ifndef ZM_VGM_PSG_GAIN
#define ZM_VGM_PSG_GAIN 4096
#endif

static vgm_seq zm_vgm;
static int zm_vgm_loaded;

uint32_t zm_vgm_load(uint8_t *file, uint32_t len, uint32_t cap) {
    zm_vgm_loaded = 0;
    if (len >= 2 && file[0] == 0x1F && file[1] == 0x8B) {
        uint32_t n = zm_gunzip_in_place(file, len, cap);
        if (!n) return ZM_VGM_PACKED;
        len = n;
    }
    int rc = vgm_open(&zm_vgm, file, len, ZM_VGM_DIV, ZM_VGM_YM_GAIN, ZM_VGM_PSG_GAIN);
    if (rc) return (uint32_t)rc;
    zm_vgm_loaded = 1;
    return ZM_VGM_OK;
}

uint32_t zm_vgm_rate(void) { return zm_vgm.rate ? zm_vgm.rate : 26633u; }

void zm_vgm_render(int16_t *lr, uint32_t n) {
    if (zm_vgm_loaded) vgm_fill(&zm_vgm, lr, n);
    else memset(lr, 0, 4u * n);
}

uint32_t zm_vgm_loops(void) { return zm_vgm.loops; }
