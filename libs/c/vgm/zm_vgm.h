/* The VGM engine's door (libs/c/vgm/README.md): load a .vgm (or a .vgz, inflated in place), render its
 * YM2612 + SN76489 PCM. The same C runs on BARD (native, fpga/host/audio_vgm.c) and in machine-audio.wasm
 * (the page's reference, machine/audio/vgm.zig), so the two render the same samples. */
#ifndef ZM_VGM_H
#define ZM_VGM_H

#include <stdint.h>

#ifndef ZM_VGM_DIV
#define ZM_VGM_DIV 2u /* the YM2612 at clock / 288: 26,634 Hz NTSC (libs/c/ym2612/ym2612.h) */
#endif

/* zm_vgm_load's answers (the player's status word carries them: libs/zig/players/vgm.zig). */
enum {
    ZM_VGM_OK = 0,
    ZM_VGM_NOT_VGM = 1, /* no "Vgm " magic (after inflating a .vgz) */
    ZM_VGM_NO_CHIP = 2, /* neither a YM2612 nor an SN76489 in the header */
    ZM_VGM_SHORT = 3,   /* shorter than its header, or its data starts past its end */
    ZM_VGM_PACKED = 4,  /* a .vgz that is corrupt, or inflates past `cap` */
};

/* Load the `len` bytes at `file` (kept while it plays). A gzip stream (.vgz) is inflated in place:
 * `cap` is the room at `file` for the inflated file. Every load starts both chips from power-on. */
uint32_t zm_vgm_load(uint8_t *file, uint32_t len, uint32_t cap);

/* The render rate, Hz (the header's YM2612 clock / 288: 26,633 for an NTSC machine). */
uint32_t zm_vgm_rate(void);

/* The next `n` frames (s16 L, R interleaved, at zm_vgm_rate) into `lr`; silence when nothing is loaded. */
void zm_vgm_render(int16_t *lr, uint32_t n);

/* The player's output (zm_vgm_out.c): the next `n` 44.1 kHz frames, resampled linearly from the engine's rate
 * and split into the four Paula channels' bytes, hi L, hi R, lo L, lo R (128 hi + lo = x >> 1 a side). */
void zm_vgm_render_paula(int8_t *hl, int8_t *hr, int8_t *ll, int8_t *lr, uint32_t n);
void zm_vgm_out_reset(uint32_t rate); /* at every load (zm_vgm_load calls it) */

/* Benches only (fpga/cycles/sound/svgmbench.c): jump `tenths` of a second into the tune, nothing rendered. */
void zm_vgm_seek(uint32_t tenths);

/* How many times the file has looped (0 in its first pass). */
uint32_t zm_vgm_loops(void);

/* SFX (zm_vgm_sfx.c): a cart's timed writes to the same chips, on the channels it owns, while the tune plays
 * (the BARD queue's YM2612 + SN76489 device: libs/zig/players/fm_live.zig, docs/project/DECISIONS.md
 * 2026-11-24 "The BARD queue's FM device"). Off by default: then nothing here changes a sample.
 * A write: `addr` ZM_SFX_YM0 + reg / ZM_SFX_YM1 + reg (the YM2612's two ports), ZM_SFX_PSG (a byte to the
 * SN76489), ZM_SFX_OWN (value: the channels the cart owns from then, ZM_SFX_FM(n) | ZM_SFX_PSG_CH(n)),
 * ZM_SFX_TUNE (value ZM_SFX_TUNE_STOP: the tune stops there, the cart's channels play on). `stamp`: the
 * output frame (44.1 kHz) it is for, counted from the device's on; it is applied at the engine frame the
 * output stage will reach then, in the order pushed. */
#define ZM_SFX_YM0 0x000u
#define ZM_SFX_YM1 0x100u
#define ZM_SFX_PSG 0x200u
#define ZM_SFX_OWN 0x300u
#define ZM_SFX_TUNE 0x301u
#define ZM_SFX_TUNE_STOP 0u
#define ZM_SFX_FM(n) (1u << (n))           /* FM channel n, 0..5 */
#define ZM_SFX_PSG_CH(n) (1u << (8u + (n))) /* PSG tone 0..2, 3 the noise */
#define ZM_SFX_OWNABLE 0x0F3Fu
enum { ZM_SFX_ST_APPLIED, ZM_SFX_ST_REFUSED, ZM_SFX_ST_PENDING, ZM_SFX_ST_LATE, ZM_SFX_ST_OUT, ZM_SFX_ST_OWN, ZM_SFX_ST_ON };

/* On: the clocks start at 0, the chips play (silent ones when no tune is loaded). Off: every channel the tune's. */
void zm_vgm_sfx_on(uint32_t on);
/* 1 queued; 0 the device is off or its ring (512) is full. */
uint32_t zm_vgm_sfx_push(uint32_t stamp, uint32_t addr, uint32_t value);
/* A counter (ZM_SFX_ST_*): writes applied, refused (a channel not owned, an unknown address), waiting, late (their
 * engine frame was rendered before they came), output frames made since on, the channels owned, on. */
uint32_t zm_vgm_sfx_stat(uint32_t i);

#endif
