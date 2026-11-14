/* The Paula channels' oscilloscopes where the players run (host/audio_scope.c): what
 * machine/audio/engine.zig's Channel.mixInto captures into `scope` for the browser's loader to
 * mirror into the cart's zigos.scopes, rebuilt from the players' `machinePaula*` calls
 * (host/audio_imports.c) because on the board no CPU runs that mix: Paula is RTL (CHORUS).
 *
 * A shadow of each channel's data, loop, step, volume and position follows the calls, and each
 * machineMixPaula piece advances it as mixInto would, sample for sample: every 4th sample is
 * captured, s * volume, into the channel's 128-entry ring, written straight as f32 bits into the
 * target (the cart's zigos.scopes, 4 x 128 f32) so the cart reads what the browser's would. No
 * float op (BARD has no FPU): the f32 product is an integer multiply and a rounding shift.
 *
 * The target: BARD's from the cart's address in C2S (cycles/snd_mailbox.h C_SCOPES), the cart
 * CPU's straight from the mirror (cycles/bmirror.c) when the players run there, a check buffer in
 * the native host (host/audio_soft.c ZM_SCOPE_CHECK). No target, no work: every call returns at once. */
#ifndef ZM_AUDIO_SCOPE_H
#define ZM_AUDIO_SCOPE_H

#include <stdint.h>

#define ZSC_CHANNELS 4u
#define ZSC_LEN 128u                                  /* engine.zig SCOPE_LEN */
#define ZSC_BYTES (4u * ZSC_CHANNELS * ZSC_LEN)       /* zigos.scopes: [4][128]f32 */

/* The rings' words (4 x 128 f32); NULL: none. A new target starts every ring from zero, as the
 * cart's statics do. */
void zsc_target(volatile uint32_t* dst);

/* The players' calls (machine/machine_audio.zig), as the engine applies them. vol_bits is the
 * f32 volume's bits: the scope holds the engine's f32 product, not the audio core's Q8 volume. */
void zsc_init(void);  /* machineAudioInit: engine.init(), every channel to its defaults */
void zsc_reset(void); /* machineAudioReset: every channel stopped, the rings cleared */
void zsc_clear(void); /* machinePaulaClearScopes */
void zsc_trigger(uint32_t ch, uint32_t data, uint32_t len, uint32_t ls, uint32_t ll);
void zsc_step(uint32_t ch, uint32_t step);
void zsc_vol(uint32_t ch, uint32_t vol_bits);
void zsc_pos(uint32_t ch, uint32_t pos);
void zsc_active(uint32_t ch, uint32_t on);
void zsc_mix(const uint8_t* mem, uint32_t off, uint32_t len); /* machineMixPaula(off, len); mem: the players' */

/* (s / 128) * vol as f32 bits, s an i8 sample: what mixInto stores, with no float op. */
uint32_t zsc_f32(int32_t s, uint32_t vol_bits);

extern uint32_t zsc_cycles; /* make snd-bench SND_SCOPES=1 only: BARD's cycles in zsc_mix since the last read */

#endif
