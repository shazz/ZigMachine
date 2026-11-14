/* The chip stepped event to event, and a sample as the box average of its ticks (zm_ay.h). Moved from
 * apps/ports/chipnomad/kestrel_ayumi.cpp (perf/ports-synth) unchanged but for two things: the counters'
 * bulk advance subtracts instead of dividing (a sample spans a handful of ticks, so a few rounds at most:
 * BARD's core has no divider, a divide is ~400 cycles there), and the state is this struct's. */
#include "zm_ay.h"
#include "zm_ay_env.h"

/* ticks until a counter that counts to `period` wraps: upstream increments, then wraps at >= period */
static inline int ticks_to_wrap(int counter, int period) { int t = period - counter; return t < 1 ? 1 : t; }

/* Advance a counter by d ticks (any number of wraps); returns the wraps. */
static inline int bulk_counter(int* counter, int period, int d) {
  int t = ticks_to_wrap(*counter, period);
  if (period < 1) period = 1;
  if (d < t) { *counter += d; return 0; }
  d -= t;
  if (d < period) { *counter = d; return 1; }
  if (period == 1) { *counter = 0; return 1 + d; }   /* a fresh chip's tones and noise */
  int w = 1;
  while (d >= period) { d -= period; w++; }          /* d is at most a sample's ticks */
  *counter = d;
  return w;
}

/* k steps of upstream's 17-bit noise LFSR (each: bit 16 <- bit 0 ^ bit 3, shift right), up to 14 at once: the
 * k new bits are bits 0..k-1 of x ^ x >> 3 while they only reach bits the shift has not replaced yet */
static void noise_advance(struct zm_ay* ay, int k) {
  unsigned x = (unsigned)ay->noise;
  while (k > 0) {
    int s = k < 14 ? k : 14;
    x = (x >> s) | (((x ^ (x >> 3)) & ((1u << s) - 1)) << (17 - s));
    k -= s;
  }
  ay->noise = (int)x;
}

/* DAC index of channel i now (upstream's update_mixer, minus the stepping) */
static inline int level(const struct zm_ay* ay, int i) {
  const struct zm_ay_tone* ch = &ay->ch[i];
  int out = (ch->tone | ch->t_off) & ((ay->noise & 1) | ch->n_off);
  return out * (ch->e_on ? ay->env : ch->volume * 2 + 1);
}

/* What the output can hear: bit i = tone i, bit 3 = noise, bit 4 = envelope. A channel whose level is 0 whatever
 * its tone and the noise do (volume 0, envelope off) hears nothing. */
static unsigned audible(const struct zm_ay* ay) {
  unsigned m = 0;
  for (int i = 0; i < ZM_AY_CHANNELS; i++) {
    const struct zm_ay_tone* ch = &ay->ch[i];
    if (!ch->e_on && ch->volume == 0) continue;
    if (!ch->t_off) m |= 1u << i;
    if (!ch->n_off) m |= 8;
    if (ch->e_on) m |= 16;
  }
  if ((m & 16) && zm_ay_env_holds(ay)) m &= ~16u;
  return m;
}

/* Step the chip `n` ticks, adding each tick's DAC level of channel i to sum[i]. Tones and noise nobody hears
 * (that set only changes with a register write) are advanced once, after the audible events. */
static void run_ticks(struct zm_ay* ay, int n, int sum[3]) {
  const int* dac = ay->dac;
  unsigned hear = audible(ay);
  int lv0 = dac[level(ay, 0)], lv1 = dac[level(ay, 1)], lv2 = dac[level(ay, 2)];
  int np2 = ay->noise_period ? ay->noise_period << 1 : 1;   /* 0 until the first set_noise: every tick, as upstream */
  int total = n;
  while (n > 0) {
    int d = n;                                     /* ticks to the next audible event, at most n */
    for (int i = 0; i < ZM_AY_CHANNELS; i++)
      if (hear >> i & 1) { int t = ticks_to_wrap(ay->ch[i].counter, ay->ch[i].period); if (t < d) d = t; }
    if (hear & 8) { int t = ticks_to_wrap(ay->noise_counter, np2); if (t < d) d = t; }
    if (hear & 16) { int t = ticks_to_wrap(ay->env_counter, ay->env_period); if (t < d) d = t; }
    /* ticks 1 .. d-1 keep the levels; at tick d the counters that wrap act, then that tick's level counts */
    sum[0] += lv0 * (d - 1); sum[1] += lv1 * (d - 1); sum[2] += lv2 * (d - 1);
    for (int i = 0; i < ZM_AY_CHANNELS; i++) {
      if (!(hear >> i & 1)) continue;
      struct zm_ay_tone* ch = &ay->ch[i];
      ch->tone ^= bulk_counter(&ch->counter, ch->period, d) & 1;
    }
    if (hear & 8) noise_advance(ay, bulk_counter(&ay->noise_counter, np2, d));
    int ew = bulk_counter(&ay->env_counter, ay->env_period, d);
    zm_ay_env_advance(ay, ew);
    lv0 = dac[level(ay, 0)]; lv1 = dac[level(ay, 1)]; lv2 = dac[level(ay, 2)];
    sum[0] += lv0; sum[1] += lv1; sum[2] += lv2;
    n -= d;
    if (ew) hear = (hear & 15) | (audible(ay) & 16);  /* an envelope that reached a hold stops mattering */
  }
  for (int i = 0; i < ZM_AY_CHANNELS; i++) {
    if (hear >> i & 1) continue;
    struct zm_ay_tone* ch = &ay->ch[i];
    ch->tone ^= bulk_counter(&ch->counter, ch->period, total) & 1;
  }
  if (!(hear & 8)) noise_advance(ay, bulk_counter(&ay->noise_counter, np2, total));
}

/* Ticks with a software oscillator: the timer runs before every tick, as upstream (it may write any
 * register), so the chip goes one tick at a time. */
static void run_ticks_timer(struct zm_ay* ay, int n, int sum[3]) {
  for (; n > 0; n--) {
    ay->timer(ay->timer_ud);
    int one[3] = {0, 0, 0};
    run_ticks(ay, 1, one);
    sum[0] += one[0]; sum[1] += one[1]; sum[2] += one[2];
  }
}

/* 65536 / n for the ticks a sample spans (n = 1 is 65536: handled apart) */
static unsigned short rcp_tab[64];

void zm_ay_process(struct zm_ay* ay) {
  unsigned t = ay->frac + ay->ticks_q16;
  int n = (int)(t >> 16);
  ay->frac = t & 0xffff;
  if (n <= 0) n = 1;                                 /* rate above clock / 8: hold one tick a sample */
  int sum[3] = {0, 0, 0};
  if (ay->timer) run_ticks_timer(ay, n, sum);
  else run_ticks(ay, n, sum);
  if (!rcp_tab[2]) for (int i = 2; i < 64; i++) rcp_tab[i] = (unsigned short)(65536u / (unsigned)i);
  /* sum[i] <= 32767 * n: sum * rcp < 2^31. n >= 64 (a rate below clock / 512) divides. */
  unsigned rcp = n >= 2 && n < 64 ? rcp_tab[n] : 65536u / (unsigned)n;
  int a0 = (int)(((unsigned)sum[0] * rcp) >> 16), a1 = (int)(((unsigned)sum[1] * rcp) >> 16), a2 = (int)(((unsigned)sum[2] * rcp) >> 16);
  ay->out_l = ((a0 * ay->pan_l[0]) >> 15) + ((a1 * ay->pan_l[1]) >> 15) + ((a2 * ay->pan_l[2]) >> 15);
  ay->out_r = ((a0 * ay->pan_r[0]) >> 15) + ((a1 * ay->pan_r[1]) >> 15) + ((a2 * ay->pan_r[2]) >> 15);
}

/* One-pole DC blocker on the sample zm_ay_process made (upstream: a 1024-sample moving average). */
void zm_ay_remove_dc(struct zm_ay* ay, int* left, int* right) {
  ay->dc_l += ((ay->out_l << 8) - ay->dc_l) >> ay->dc_shift;
  ay->dc_r += ((ay->out_r << 8) - ay->dc_r) >> ay->dc_shift;
  *left = ay->out_l - (ay->dc_l >> 8);
  *right = ay->out_r - (ay->dc_r >> 8);
}
