/* Up to eight AYs behind one address space: the BARD queue's AY device (libs/zig/players/sid_live.zig, the
 * cart's ring entry {t, addr, value}, addr = 0xA000 + the offset below). BARD runs it natively
 * (fpga/host/audio_ay.c), the page in machine-audio.wasm (machine/audio/ay.zig): the same C.
 *
 *   0x00 + chip x 16 + reg   reg 0..13: the chip's register (zm_ay_write)
 *                            reg 14: configure: value bits 0-23 the clock in Hz, bit 24 YM (else AY); a fresh chip
 *                                    (a clock under 8 Hz: the chip off)
 *                            reg 15: stereo: bits 0-7, 8-15, 16-23 the pans of A, B, C (k / 200, 0 left .. 200
 *                                    right), bit 24 equal-power (else linear)
 *   0x80 + chip              the chip's gain in the mix, Q15 (32768 = 1, the default)
 *
 * A chip plays from its first configure; anything else for a chip not configured is refused. */
#ifndef ZM_AY_BANK_H
#define ZM_AY_BANK_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ZM_AY_BANK_CHIPS 8
#define ZM_AY_BANK_RATE 44100u  /* the queue's clock: one rendered frame a stamp */
#define ZM_AY_REG_CONFIG 14
#define ZM_AY_REG_STEREO 15
#define ZM_AY_GAIN_BASE 0x80u
#define ZM_AY_CFG_YM (1u << 24)
#define ZM_AY_PAN_EQP (1u << 24)

/* Every chip off (silence). */
void zm_ay_bank_reset(void);
/* A write at offset `a` (0..0xFF). 1: applied; 0: refused (no such address, or the chip not configured). */
int zm_ay_bank_write(uint32_t a, uint32_t value);
/* The next `n` stereo frames (L, R interleaved, s16) at ZM_AY_BANK_RATE: the configured chips summed, clamped. */
void zm_ay_bank_render(int16_t* stereo, uint32_t n);
/* Chips configured (bit i: chip i). */
uint32_t zm_ay_bank_on(void);

#ifdef __cplusplus
}
#endif
#endif
