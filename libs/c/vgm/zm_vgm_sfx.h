/* The SFX device's hooks inside the engine (zm_vgm_sfx.c; its door is in zm_vgm.h). With the device off
 * every hook is a pass-through: the tune's writes reach the chips as before, nothing is held back. */
#ifndef ZM_VGM_SFX_H
#define ZM_VGM_SFX_H

#include "vgm_seq.h"

/* The tune's writes, through the channel owner's filter (a write to an SFX-owned channel is kept aside). */
void zm_sfx_music_ym(vgm_seq *v, uint32_t port, uint32_t reg, uint32_t val);
void zm_sfx_music_psg(vgm_seq *v, uint32_t byte);
/* Before rendering up to `k` engine frames: the SFX writes due now applied; returns the frames to render
 * before the next one is due (at most k, at least 1). */
uint32_t zm_sfx_due(vgm_seq *v, uint32_t k);
/* `k` engine frames rendered (the device's engine clock). */
void zm_sfx_rendered(uint32_t k);
/* `n` output frames made by the output stage (the device's stamp clock). */
void zm_sfx_output(uint32_t n);
/* A tune was loaded (the chips were reset): the SFX channels' state put back, the clocks re-tied. */
void zm_sfx_loaded(vgm_seq *v);

/* The device on or off (zm_vgm_sfx_on); off gives the tune back every channel. */
void zm_sfx_switch(vgm_seq *v, uint32_t on);

/* zm_vgm_out.c: how many engine frames after the next one the engine renders the output stage will take
 * when it is about to make the output frame `d` frames from now (negative: that frame is rendered already). */
int32_t zm_vgm_out_lead(uint32_t d);

#endif
