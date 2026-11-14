/* The AY-3-8910 / YM2149 in integers: one model for every CPU that renders one (README.md).
 *
 * ayumi's chip (Peter Sovietov, modifications by Megus; MIT): tone counters, the 17-bit noise LFSR, the
 * 32-step envelope and its 16 shapes, the AY / YM DAC tables, the pans, all stepped a chip tick (clock / 8)
 * at a time. A sample is the exact average of the chip's output over the ticks it spans (a box filter),
 * and the chip is stepped event to event (the next tone edge, noise or envelope step), not tick by tick.
 * No float, no divide in the per-sample path (BARD has neither an FPU nor a divider).
 *
 * Who runs it: ChipNomad's cart on ZIGGY (apps/ports/chipnomad/kestrel_ayumi.cpp: upstream's ayumi API, a
 * thin float wrapper over this), BARD natively (fpga/host/audio_ay.c) and machine-audio.wasm on the page
 * (machine/audio/ay.zig), both through zm_ay_bank.h. */
#ifndef ZM_AY_H
#define ZM_AY_H

#ifdef __cplusplus
extern "C" {
#endif

#define ZM_AY_CHANNELS 3
#define ZM_AY_PAN_STEPS 200 /* a pan is k / 200, k = 0 (left) .. 200 (right) */

struct zm_ay_tone {
  int period, counter, tone;
  int t_off, n_off, e_on, volume;
};

struct zm_ay {
  struct zm_ay_tone ch[ZM_AY_CHANNELS];
  int noise_period, noise_counter, noise;
  int env_counter, env_period, env_shape, env_segment, env;
  const int* dac;          /* 32 levels, Q15 */
  unsigned rate, clock;    /* output samples a second; the chip's clock in Hz */
  unsigned ticks_q16;      /* chip ticks (clock / 8) a sample, 16.16 */
  unsigned frac;           /* the fraction of a tick carried to the next sample */
  int pan_l[ZM_AY_CHANNELS], pan_r[ZM_AY_CHANNELS]; /* Q15 */
  int out_l, out_r;        /* the last sample, Q15, before DC removal */
  int dc_l, dc_r;          /* DC estimate, Q23 */
  int dc_shift;            /* the one-pole's corner: ~14 Hz at any rate */
  unsigned char regs[16];  /* the register file as written (zm_ay_write) */
  int (*timer)(void* ud);  /* a software oscillator, run before every tick (NULL: none) */
  void* timer_ud;
};

/* A fresh chip: registers 0, the mixer 0x3F, centred pans. `rate` > 0, `clock` >= 8. */
void zm_ay_init(struct zm_ay* ay, int is_ym, unsigned clock, unsigned rate);
void zm_ay_set_clock(struct zm_ay* ay, unsigned clock);
void zm_ay_set_type(struct zm_ay* ay, int is_ym);
/* Channel `i`'s pan k / 200 (0..200), equal-power (sqrt) or linear, from integer tables. */
void zm_ay_set_pan(struct zm_ay* ay, int i, int k, int is_eqp);
void zm_ay_set_pan_q15(struct zm_ay* ay, int i, int left, int right);
/* The Q15 gain of pan k / 200 on its right side (left: 200 - k). */
int zm_ay_pan_q15(int k, int is_eqp);

void zm_ay_set_tone(struct zm_ay* ay, int i, int period);
void zm_ay_set_noise(struct zm_ay* ay, int period);
void zm_ay_set_mixer(struct zm_ay* ay, int i, int t_off, int n_off, int e_on);
void zm_ay_set_volume(struct zm_ay* ay, int i, int volume);
void zm_ay_set_envelope(struct zm_ay* ay, int period);
void zm_ay_set_envelope_shape(struct zm_ay* ay, int shape);
/* Register `reg` (0..13) as the chip takes it; 14, 15 (the I/O ports: no sound) are ignored, as ChipNomad does. */
void zm_ay_write(struct zm_ay* ay, int reg, int value);
void zm_ay_set_timer(struct zm_ay* ay, int (*timer)(void* ud), void* ud);

/* One sample into out_l / out_r (Q15, before DC removal). */
void zm_ay_process(struct zm_ay* ay);
/* The sample zm_ay_process made, with its DC removed (Q15). */
void zm_ay_remove_dc(struct zm_ay* ay, int* left, int* right);

#ifdef __cplusplus
}
#endif
#endif
