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

#endif
