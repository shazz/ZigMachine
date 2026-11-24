/* The VGM engine's door (zm_vgm.h): the sequencer (vgm_seq.c) over our YM2612 (libs/c/ym2612) and
 * SN76489 (libs/c/sn76489), one instance. Built for machine-audio.wasm (build.zig) and natively
 * (fpga/host/audio_vgm.c). Our own code. */
#include "zm_vgm.h"

#include "zm_mem.h"

#include "vgm_seq.h"
#include "zm_vgm_sfx.h"
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
static void zm_vgm_live(void);

uint32_t zm_vgm_load(uint8_t *file, uint32_t len, uint32_t cap) {
    zm_vgm_loaded = 0;
    if (len >= 2 && file[0] == 0x1F && file[1] == 0x8B) {
        uint32_t n = zm_gunzip_in_place(file, len, cap);
        if (!n) return ZM_VGM_PACKED;
        len = n;
    }
    int rc = vgm_open(&zm_vgm, file, len, ZM_VGM_DIV, ZM_VGM_YM_GAIN, ZM_VGM_PSG_GAIN);
    if (rc) {
        if (zm_vgm_sfx_stat(ZM_SFX_ST_ON)) zm_vgm_live(); /* the cart's channels play on, over no tune */
        return (uint32_t)rc;
    }
    zm_vgm_loaded = 1;
    zm_vgm_out_reset(zm_vgm.rate);
    if (zm_vgm_sfx_stat(ZM_SFX_ST_ON)) {
        zm_vgm.has_ym = zm_vgm.has_psg = 1; /* the cart may use a chip the tune does not */
        zm_sfx_loaded(&zm_vgm);
    }
    return ZM_VGM_OK;
}

/* No tune: both chips from power-on at an NTSC Mega Drive's clocks, nothing to sequence (the SFX device's own). */
static void zm_vgm_live(void) {
    vgm_seq *v = &zm_vgm;
    memset(v, 0, sizeof *v);
    v->has_ym = v->has_psg = 1;
    v->ended = 1;
    v->rate = 7670453u / (144u * (ZM_VGM_DIV == 1 ? 1u : 2u));
    ym2612_reset(&v->ym, ZM_VGM_DIV);
    v->ym.gain = ZM_VGM_YM_GAIN;
    sn76489_reset(&v->psg, 3579545u, v->rate, ZM_VGM_PSG_GAIN);
    zm_vgm_loaded = 1;
    zm_vgm_out_reset(v->rate);
    zm_sfx_loaded(v);
}

void zm_vgm_sfx_on(uint32_t on) {
    zm_sfx_switch(&zm_vgm, on);
    if (on && !zm_vgm_loaded) zm_vgm_live();
}

uint32_t zm_vgm_rate(void) { return zm_vgm.rate ? zm_vgm.rate : 26633u; }

void zm_vgm_render(int16_t *lr, uint32_t n) {
    if (zm_vgm_loaded) vgm_fill(&zm_vgm, lr, n);
    else memset(lr, 0, 4u * n);
}

uint32_t zm_vgm_loops(void) { return zm_vgm.loops; }

void zm_vgm_seek(uint32_t tenths) {
    if (zm_vgm_loaded) vgm_seek(&zm_vgm, tenths * 4410u);
}
