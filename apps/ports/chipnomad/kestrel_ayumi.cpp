/* ayumi for the cart CPU: replaces upstream's ayumi.cpp (Peter Sovietov, modifications by Megus; MIT, see
 * upstream's chipnomad_lib/external/ayumi/LICENSE) with the same API, the same struct and the same chip model:
 * tone counters, the 17-bit noise LFSR, the 32-step envelope and its 16 shapes, the AY / YM DAC tables, the pans,
 * all stepped once a chip tick (clock / 8), and the timer callback (ChipNomad's software oscillators) once a tick
 * before the mixer, as upstream.
 *
 * What differs is the resampling. Upstream runs 8 substeps a sample, a cubic interpolator and a 19- to 96-tap FIR
 * in float, which costs ~4,600 cycles a 44.1 kHz sample on ZIGGY (apps/frame_cost.mjs) and needs rate >= clock / 64.
 * Here a sample is the exact average of the chip's output over the ticks it spans (a box filter, as most YM
 * emulators): integers only, and the chip is stepped event to event (the next tone edge, noise or envelope step)
 * rather than tick by tick. A tone, the noise or the envelope that no channel can hear right now is advanced in
 * bulk. Any rate works: ChipNomad runs at 22050 Hz on the cart. The 1024-sample moving-average DC filter becomes
 * a one-pole high-pass (~14 Hz at 22050 Hz).
 * The quality setting (ayumi_set_filter_quality) is kept but has nothing to choose any more. */
#include <string.h>
#include <math.h>
#include "ayumi.h"

/* upstream's DAC tables in Q15 (round(x * 32767)), two entries a 4-bit level as upstream */
static const int AY_dac[32] = {
  0, 0, 327, 327, 473, 473, 690, 690, 1006, 1006, 1492, 1492, 2113, 2113, 3518, 3518,
  4148, 4148, 6717, 6717, 9575, 9575, 12217, 12217, 16139, 16139, 20818, 20818, 26396, 26396, 32767, 32767
};
static const int YM_dac[32] = {
  0, 0, 152, 253, 359, 457, 557, 656, 798, 973, 1149, 1323, 1590, 1911, 2230, 2549,
  3031, 3640, 4251, 4865, 5789, 6932, 8073, 9211, 10935, 13121, 15315, 17512, 20813, 24837, 28832, 32767
};
/* ayumi's dac_table field points at one of these (the struct keeps upstream's float pointer type) */
#define DAC(ay) ((const int *)(const void *)(ay)->dac_table)

enum { SLIDE_DOWN, SLIDE_UP, HOLD_TOP, HOLD_BOTTOM };
static const unsigned char Envelopes[16][2] = {
  {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, HOLD_BOTTOM},
  {SLIDE_UP, HOLD_BOTTOM}, {SLIDE_UP, HOLD_BOTTOM}, {SLIDE_UP, HOLD_BOTTOM}, {SLIDE_UP, HOLD_BOTTOM},
  {SLIDE_DOWN, SLIDE_DOWN}, {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, SLIDE_UP}, {SLIDE_DOWN, HOLD_TOP},
  {SLIDE_UP, SLIDE_UP}, {SLIDE_UP, HOLD_TOP}, {SLIDE_UP, SLIDE_DOWN}, {SLIDE_UP, HOLD_BOTTOM}
};

static int env_action(const struct ayumi* ay) { return Envelopes[ay->envelope_shape][ay->envelope_segment]; }

static void reset_segment(struct ayumi* ay) {
  int a = env_action(ay);
  ay->envelope = (a == SLIDE_DOWN || a == HOLD_TOP) ? 31 : 0;
}

/* k envelope counter wraps (upstream: Envelopes[shape][segment](ay) once a wrap), a slide at a time */
static void env_advance(struct ayumi* ay, int k) {
  while (k > 0) {
    int a = env_action(ay);
    if (a == HOLD_TOP || a == HOLD_BOTTOM) return;
    int room = a == SLIDE_UP ? 32 - ay->envelope : ay->envelope + 1;   /* wraps until it leaves 0..31 */
    int s = k < room ? k : room;
    ay->envelope += a == SLIDE_UP ? s : -s;
    k -= s;
    if (ay->envelope < 0 || ay->envelope > 31) { ay->envelope_segment ^= 1; reset_segment(ay); }
  }
}

/* k steps of upstream's 17-bit noise LFSR (each: bit 16 <- bit 0 ^ bit 3, shift right), up to 14 at once: the
 * k new bits are bits 0..k-1 of x ^ x >> 3 while they only reach bits the shift has not replaced yet */
static void noise_advance(struct ayumi* ay, int k) {
  unsigned x = (unsigned)ay->noise;
  while (k > 0) {
    int s = k < 14 ? k : 14;
    x = (x >> s) | (((x ^ (x >> 3)) & ((1u << s) - 1)) << (17 - s));
    k -= s;
  }
  ay->noise = (int)x;
}

/* ticks until a counter that counts to `period` wraps: upstream increments, then wraps at >= period */
static inline int ticks_to_wrap(int counter, int period) { int t = period - counter; return t < 1 ? 1 : t; }

/* Advance a counter by d ticks (any number of wraps); returns the wraps. */
static inline int bulk_counter(int* counter, int period, int d) {
  int t = ticks_to_wrap(*counter, period);
  if (period < 1) period = 1;
  if (d < t) { *counter += d; return 0; }
  d -= t;
  if (d < period) { *counter = d; return 1; }
  if (period == 1) { *counter = 0; return 1 + d; }   /* a fresh chip's tones and noise: no divide */
  *counter = d % period;
  return 1 + d / period;
}

/* DAC index of channel i now (upstream's update_mixer, minus the stepping) */
static inline int level(const struct ayumi* ay, int i) {
  const struct tone_channel* ch = &ay->channels[i];
  int out = (ch->tone | ch->t_off) & ((ay->noise & 1) | ch->n_off);
  return out * (ch->e_on ? ay->envelope : ch->volume * 2 + 1);
}

/* What the output can hear: bit i = tone i, bit 3 = noise, bit 4 = envelope. A channel whose level is 0 whatever
 * its tone and the noise do (volume 0, envelope off) hears nothing. */
static unsigned audible(const struct ayumi* ay) {
  unsigned m = 0;
  for (int i = 0; i < TONE_CHANNELS; i++) {
    const struct tone_channel* ch = &ay->channels[i];
    if (!ch->e_on && ch->volume == 0) continue;
    if (!ch->t_off) m |= 1u << i;
    if (!ch->n_off) m |= 8;
    if (ch->e_on) m |= 16;
  }
  if (m & 16) { int a = env_action(ay); if (a == HOLD_TOP || a == HOLD_BOTTOM) m &= ~16u; }
  return m;
}

/* Step the chip `n` ticks, adding each tick's DAC level of channel i to sum[i]. Tones and noise nobody hears
 * (that set only changes with a register write) are advanced once, after the audible events. */
static void run_ticks(struct ayumi* ay, int n, int sum[3]) {
  const int* dac = DAC(ay);
  unsigned hear = audible(ay);
  int lv0 = dac[level(ay, 0)], lv1 = dac[level(ay, 1)], lv2 = dac[level(ay, 2)];
  int np2 = ay->noise_period ? ay->noise_period << 1 : 1;   /* 0 until the first set_noise: every tick, as upstream */
  int total = n;
  while (n > 0) {
    int d = n;                                     /* ticks to the next audible event, at most n */
    for (int i = 0; i < TONE_CHANNELS; i++)
      if (hear >> i & 1) { int t = ticks_to_wrap(ay->channels[i].tone_counter, ay->channels[i].tone_period); if (t < d) d = t; }
    if (hear & 8) { int t = ticks_to_wrap(ay->noise_counter, np2); if (t < d) d = t; }
    if (hear & 16) { int t = ticks_to_wrap(ay->envelope_counter, ay->envelope_period); if (t < d) d = t; }
    /* ticks 1 .. d-1 keep the levels; at tick d the counters that wrap act, then that tick's level counts */
    sum[0] += lv0 * (d - 1); sum[1] += lv1 * (d - 1); sum[2] += lv2 * (d - 1);
    for (int i = 0; i < TONE_CHANNELS; i++) {
      if (!(hear >> i & 1)) continue;
      struct tone_channel* ch = &ay->channels[i];
      ch->tone ^= bulk_counter(&ch->tone_counter, ch->tone_period, d) & 1;
    }
    if (hear & 8) noise_advance(ay, bulk_counter(&ay->noise_counter, np2, d));
    int ew = bulk_counter(&ay->envelope_counter, ay->envelope_period, d);
    env_advance(ay, ew);
    lv0 = dac[level(ay, 0)]; lv1 = dac[level(ay, 1)]; lv2 = dac[level(ay, 2)];
    sum[0] += lv0; sum[1] += lv1; sum[2] += lv2;
    n -= d;
    if (ew) hear = (hear & 15) | (audible(ay) & 16);  /* an envelope that reached a hold stops mattering */
  }
  for (int i = 0; i < TONE_CHANNELS; i++) {
    if (hear >> i & 1) continue;
    struct tone_channel* ch = &ay->channels[i];
    ch->tone ^= bulk_counter(&ch->tone_counter, ch->tone_period, total) & 1;
  }
  if (!(hear & 8)) noise_advance(ay, bulk_counter(&ay->noise_counter, np2, total));
}

/* Ticks with ChipNomad's software oscillators: the timer runs before every tick, as upstream (it may write any
 * register), so the chip goes one tick at a time. */
static void run_ticks_timer(struct ayumi* ay, int n, int sum[3]) {
  for (; n > 0; n--) {
    ay->timer_func(ay, ay->timer_func_userdata);
    int one[3] = {0, 0, 0};
    run_ticks(ay, 1, one);
    sum[0] += one[0]; sum[1] += one[1]; sum[2] += one[2];
  }
}

static void update_rate(struct ayumi* ay) {
  ay->k.step_seen = ay->step;
  ay->k.ticks_q16 = (unsigned)(ay->step * (float)(DECIMATE_FACTOR * 65536));
}

int ayumi_configure(struct ayumi* ay, int is_ym, float clock_rate, int sr) {
  memset(ay, 0, sizeof(struct ayumi));
  ay->step = clock_rate / (sr * 8 * DECIMATE_FACTOR);
  ayumi_set_chip_type(ay, is_ym);
  ay->noise = 1;
  ay->filter_func = ayumi_filter_medium;
  ayumi_set_envelope(ay, 1);
  for (int i = 0; i < TONE_CHANNELS; i += 1) ayumi_set_tone(ay, i, 1);
  update_rate(ay);
  return ay->step < 1;
}

void ayumi_set_chip_type(struct ayumi* ay, int is_ym) {
  ay->dac_table = (const float*)(const void*)(is_ym ? YM_dac : AY_dac);
}

void ayumi_set_pan(struct ayumi* ay, int index, float pan, int is_eqp) {
  float l = is_eqp ? sqrtf(1 - pan) : 1 - pan, r = is_eqp ? sqrtf(pan) : pan;
  ay->channels[index].pan_left = l;
  ay->channels[index].pan_right = r;
  ay->k.pan_l[index] = (int)(l * 32768.0f + 0.5f);
  ay->k.pan_r[index] = (int)(r * 32768.0f + 0.5f);
}

void ayumi_set_tone(struct ayumi* ay, int index, int period) {
  period &= 0xfff;
  ay->channels[index].tone_period = (period == 0) | period;
}

void ayumi_set_noise(struct ayumi* ay, int period) {
  period &= 0x1f;
  ay->noise_period = (period == 0) | period;
}

void ayumi_set_mixer(struct ayumi* ay, int index, int t_off, int n_off, int e_on) {
  ay->channels[index].t_off = t_off & 1;
  ay->channels[index].n_off = n_off & 1;
  ay->channels[index].e_on = e_on;
}

void ayumi_set_volume(struct ayumi* ay, int index, int volume) { ay->channels[index].volume = volume & 0xf; }

void ayumi_set_envelope(struct ayumi* ay, int period) {
  period &= 0xffff;
  ay->envelope_period = (period == 0) | period;
}

void ayumi_set_envelope_shape(struct ayumi* ay, int shape) {
  ay->envelope_shape = shape & 0xf;
  ay->envelope_counter = 0;
  ay->envelope_segment = 0;
  reset_segment(ay);
}

void ayumi_set_filter_quality(struct ayumi* ay, ayumi_filter_func filter_func) { ay->filter_func = filter_func; }

void ayumi_set_timer_func(struct ayumi* ay, int (*timer_func)(struct ayumi* ay, void* userdata), void* timer_func_userdata) {
  ay->timer_func = timer_func;
  ay->timer_func_userdata = timer_func_userdata;
}

/* One output sample into ay->k.out_l / out_r (Q15, before DC removal). */
void ayumi_process(struct ayumi* ay) {
  struct kestrel_ay* k = &ay->k;
  if (ay->step != k->step_seen) update_rate(ay);    /* SoundChipAY::updateClock writes ay->step */
  unsigned t = k->frac + k->ticks_q16;
  int n = (int)(t >> 16);
  k->frac = t & 0xffff;
  if (n <= 0) n = 1;                                 /* rate above clock / 8: hold one tick a sample */
  int sum[3] = {0, 0, 0};
  if (ay->timer_func) run_ticks_timer(ay, n, sum);
  else run_ticks(ay, n, sum);
  static unsigned short rcp_tab[64];                 /* 65536 / n (n = 1 is 65536: the else branch) */
  if (!rcp_tab[2]) for (int i = 2; i < 64; i++) rcp_tab[i] = (unsigned short)(65536u / (unsigned)i);
  unsigned rcp = n >= 2 && n < 64 ? rcp_tab[n] : 65536u / (unsigned)n;   /* sum[i] <= 32767 * n: sum * rcp < 2^31 */
  int a0 = (int)(((unsigned)sum[0] * rcp) >> 16), a1 = (int)(((unsigned)sum[1] * rcp) >> 16), a2 = (int)(((unsigned)sum[2] * rcp) >> 16);
  k->out_l = ((a0 * k->pan_l[0]) >> 15) + ((a1 * k->pan_l[1]) >> 15) + ((a2 * k->pan_l[2]) >> 15);
  k->out_r = ((a0 * k->pan_r[0]) >> 15) + ((a1 * k->pan_r[1]) >> 15) + ((a2 * k->pan_r[2]) >> 15);
  ay->left = (float)k->out_l * (1.0f / 32768.0f);
  ay->right = (float)k->out_r * (1.0f / 32768.0f);
}

/* One-pole DC blocker on the sample ayumi_process made (upstream: a 1024-sample moving average). */
void ayumi_remove_dc(struct ayumi* ay) {
  struct kestrel_ay* k = &ay->k;
  k->dc_l += ((k->out_l << 8) - k->dc_l) >> 8;
  k->dc_r += ((k->out_r << 8) - k->dc_r) >> 8;
  ay->left = (float)(k->out_l - (k->dc_l >> 8)) * (1.0f / 32768.0f);
  ay->right = (float)(k->out_r - (k->dc_r >> 8)) * (1.0f / 32768.0f);
}
