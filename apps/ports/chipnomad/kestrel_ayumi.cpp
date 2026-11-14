/* ayumi for the cart CPU: replaces upstream's ayumi.cpp (Peter Sovietov, modifications by Megus; MIT, see
 * upstream's chipnomad_lib/external/ayumi/LICENSE) with the same API over the integer AY core every renderer
 * shares (libs/c/ayumi: the cart on ZIGGY here, BARD natively, the page in machine-audio.wasm). The chip is
 * upstream's model stepped event to event; a sample is the exact average of its chip ticks (a box filter) instead
 * of the cubic interpolator + FIR; a one-pole DC blocker (libs/c/ayumi/README.md).
 *
 * This file is only upstream's float set-up turned into the core's integers: the clock (ay->step, which
 * SoundChipAY::updateClock writes directly, read back as Hz), the pans (k / 200 from the core's table: every pan
 * ChipNomad makes is one), and the float output upstream's callers read. The core's state rides at the end of
 * struct ayumi (patches/ayumi.h.sed). The quality setting (ayumi_set_filter_quality) has nothing to choose. */
#include <string.h>
#include <math.h>
#include "ayumi.h"

/* The clock behind upstream's float step (clock / (rate x 8 x DECIMATE_FACTOR)), exact for every clock below 2^24. */
static unsigned clock_of(const struct ayumi* ay) {
  return (unsigned)(ay->step * (float)(ay->k.rate * 8 * DECIMATE_FACTOR) + 0.5f);
}

int ayumi_configure(struct ayumi* ay, int is_ym, float clock_rate, int sr) {
  memset(ay, 0, sizeof(struct ayumi));
  ay->step = clock_rate / (sr * 8 * DECIMATE_FACTOR);
  ay->step_seen = ay->step;
  ay->filter_func = ayumi_filter_medium;
  zm_ay_init(&ay->k, is_ym, (unsigned)(clock_rate + 0.5f), (unsigned)sr);
  for (int i = 0; i < TONE_CHANNELS; i++) zm_ay_set_pan_q15(&ay->k, i, 0, 0);   /* upstream: silent until set_pan */
  return ay->step < 1;
}

void ayumi_set_chip_type(struct ayumi* ay, int is_ym) { zm_ay_set_type(&ay->k, is_ym); }

void ayumi_set_pan(struct ayumi* ay, int index, float pan, int is_eqp) {
  float l = is_eqp ? sqrtf(1 - pan) : 1 - pan, r = is_eqp ? sqrtf(pan) : pan;
  ay->channels[index].pan_left = l;
  ay->channels[index].pan_right = r;
  float k = pan * ZM_AY_PAN_STEPS;
  int ki = (int)(k + 0.5f);
  if (ki >= 0 && ki <= ZM_AY_PAN_STEPS && fabsf(k - (float)ki) < 1e-3f) zm_ay_set_pan(&ay->k, index, ki, is_eqp);
  else zm_ay_set_pan_q15(&ay->k, index, (int)(l * 32768.0f + 0.5f), (int)(r * 32768.0f + 0.5f));
}

void ayumi_set_tone(struct ayumi* ay, int index, int period) { zm_ay_set_tone(&ay->k, index, period); }
void ayumi_set_noise(struct ayumi* ay, int period) { zm_ay_set_noise(&ay->k, period); }
void ayumi_set_mixer(struct ayumi* ay, int index, int t_off, int n_off, int e_on) { zm_ay_set_mixer(&ay->k, index, t_off, n_off, e_on); }
void ayumi_set_volume(struct ayumi* ay, int index, int volume) { zm_ay_set_volume(&ay->k, index, volume); }
void ayumi_set_envelope(struct ayumi* ay, int period) { zm_ay_set_envelope(&ay->k, period); }
void ayumi_set_envelope_shape(struct ayumi* ay, int shape) { zm_ay_set_envelope_shape(&ay->k, shape); }
void ayumi_set_filter_quality(struct ayumi* ay, ayumi_filter_func filter_func) { ay->filter_func = filter_func; }

/* ChipNomad's software oscillators: the core calls this before every tick. */
static int timer_tramp(void* p) {
  struct ayumi* ay = (struct ayumi*)p;
  return ay->timer_func(ay, ay->timer_func_userdata);
}

void ayumi_set_timer_func(struct ayumi* ay, int (*timer_func)(struct ayumi* ay, void* userdata), void* timer_func_userdata) {
  ay->timer_func = timer_func;
  ay->timer_func_userdata = timer_func_userdata;
  zm_ay_set_timer(&ay->k, timer_func ? timer_tramp : NULL, ay);
}

void ayumi_process(struct ayumi* ay) {
  if (ay->step != ay->step_seen) { ay->step_seen = ay->step; zm_ay_set_clock(&ay->k, clock_of(ay)); }
  zm_ay_process(&ay->k);
  ay->left = (float)ay->k.out_l * (1.0f / 32768.0f);
  ay->right = (float)ay->k.out_r * (1.0f / 32768.0f);
}

void ayumi_remove_dc(struct ayumi* ay) {
  int l, r;
  zm_ay_remove_dc(&ay->k, &l, &r);
  ay->left = (float)l * (1.0f / 32768.0f);
  ay->right = (float)r * (1.0f / 32768.0f);
}
