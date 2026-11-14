// libs/c/ayumi (the integer core) against the cart's ayumi of perf/ports-synth (check.sh builds it from git):
// random chips (AY / YM, ChipNomad's clocks and random ones, 22050 and 44100 Hz, every stereo separation), random
// register writes between samples (as ChipNomad's SoundChipAY::setRegister decodes them), clock changes (its
// updateClock), and a software oscillator writing registers before every tick. Every sample must be the same:
// out_l / out_r, and after the DC blocker at 22050 Hz (the old one's corner; at 44100 the core's is halved
// to keep ~14 Hz, so there only the samples before it are compared).
//   check [--break]    --break: the core's tone writes are off by one, which must be caught
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "ayumi.h"   // old_ayumi.h
#include "zm_ay.h"

static unsigned seed = 12345;
static unsigned rnd(unsigned n) { seed = seed * 1103515245u + 12345u; return (seed >> 8) % n; }
static int broke;

// ChipNomad's SoundChipAY on the old ayumi (chip_ay.cpp setRegister, setPanning, updateClock)
struct OldChip {
  struct ayumi ay;
  unsigned char r[16];
  int rate;
  void write(int reg, int v) {
    if (reg > 13) return;
    r[reg] = (unsigned char)v;
    if (reg <= 5) ayumi_set_tone(&ay, reg >> 1, r[reg | 1] << 8 | r[reg & ~1]);
    else if (reg == 6) ayumi_set_noise(&ay, r[6]);
    else if (reg <= 10) {
      for (int i = 0; i < 3; i++) ayumi_set_mixer(&ay, i, r[7] >> i & 1, r[7] >> (3 + i) & 1, r[8 + i] >> 4);
      for (int i = 0; i < 3; i++) ayumi_set_volume(&ay, i, r[8 + i] & 0xf);
    } else if (reg <= 12) ayumi_set_envelope(&ay, r[12] << 8 | r[11]);
    else ayumi_set_envelope_shape(&ay, r[13]);
  }
  void pans(int separation) {
    float sep = (float)separation / 200.0;
    ayumi_set_pan(&ay, 0, 0.5 - sep, 1);
    ayumi_set_pan(&ay, 1, 0.5, 1);
    ayumi_set_pan(&ay, 2, 0.5 + sep, 1);
  }
};

// A software oscillator: the same register writes on both chips, from its own generator.
struct Osc { unsigned s; int n; };
static void osc_step(Osc* o, int* reg, int* v) {
  o->s = o->s * 69069u + 1u;
  *reg = (o->s >> 12) % 3 == 0 ? 8 + (int)((o->s >> 16) % 3) : (int)((o->s >> 16) % 6);
  *v = (int)(o->s >> 20) & 0xff;
}
static Osc osc_old, osc_new;
static int old_timer(struct ayumi* ay, void* ud) {
  int reg, v; osc_step(&osc_old, &reg, &v);
  ((OldChip*)ud)->write(reg, v); (void)ay; return 0;
}
static int new_timer(void* ud) {
  int reg, v; osc_step(&osc_new, &reg, &v);
  zm_ay_write((struct zm_ay*)ud, reg, v); return 0;
}

static int random_value(int reg) {
  switch (reg) {
  case 0: case 2: case 4: return (int)rnd(256);
  case 1: case 3: case 5: return rnd(4) ? (int)rnd(4) : (int)rnd(16);
  case 6: return (int)rnd(32);
  case 7: return (int)rnd(64);
  case 8: case 9: case 10: return rnd(5) ? (int)rnd(16) : 16 | (int)rnd(16);
  case 11: return (int)rnd(256);
  case 12: return rnd(3) ? 0 : (int)rnd(8);
  default: return (int)rnd(16);
  }
}

static const unsigned CLOCKS[] = {1773400, 1750000, 2000000, 1000000, 3500000, 1789772};

static int one_case(int c, long* samples) {
  static OldChip o;
  static struct zm_ay n;
  int rate = c & 1 ? 44100 : 22050, ym = (int)rnd(2), sep = (int)rnd(101);
  unsigned clock = c % 7 == 6 ? 1000000 + rnd(3000000) : CLOCKS[rnd(6)];
  memset(&o, 0, sizeof o);
  o.r[7] = 0x3f;                               // SoundChipAY's constructor
  o.rate = rate;
  ayumi_configure(&o.ay, ym, (float)clock, rate);
  o.pans(sep);
  zm_ay_init(&n, ym, clock, (unsigned)rate);
  o.ay.k.ticks_q16 = n.ticks_q16;              // the set-up's rounding is ticks_sweep's; here the stepping
  zm_ay_set_pan(&n, 0, 100 - sep, 1); zm_ay_set_pan(&n, 1, 100, 1); zm_ay_set_pan(&n, 2, 100 + sep, 1);
  int timer = c % 5 == 4;
  if (timer) {
    osc_old.s = osc_new.s = (unsigned)c;
    ayumi_set_timer_func(&o.ay, old_timer, &o);
    zm_ay_set_timer(&n, new_timer, &n);
  }
  int len = timer ? 400 : 4000;
  for (int s = 0; s < len; s++) {
    if (rnd(8) == 0) for (int k = (int)rnd(4); k >= 0; k--) {
      int reg = (int)rnd(14), v = random_value(reg);
      o.write(reg, v);
      zm_ay_write(&n, reg, broke && reg <= 5 ? v ^ 1 : v);
    }
    if (rnd(2000) == 0) {                      // updateClock
      clock = CLOCKS[rnd(6)];
      o.ay.step = (float)clock / (rate * 8 * 8);
      zm_ay_set_clock(&n, clock);
      o.ay.k.step_seen = o.ay.step, o.ay.k.ticks_q16 = n.ticks_q16;
    }
    ayumi_process(&o.ay);
    zm_ay_process(&n);
    int ol = o.ay.k.out_l, orr = o.ay.k.out_r;
    if (ol != n.out_l || orr != n.out_r) {
      printf("case %d (clock %u, %d Hz, %s, timer %d) sample %d: old %d %d, core %d %d\n",
             c, clock, rate, ym ? "YM" : "AY", timer, s, ol, orr, n.out_l, n.out_r);
      return 0;
    }
    ayumi_remove_dc(&o.ay);
    int dl, dr;
    zm_ay_remove_dc(&n, &dl, &dr);
    if (rate == 22050 && (o.ay.left != dl * (1.0f / 32768.0f) || o.ay.right != dr * (1.0f / 32768.0f))) {
      printf("case %d sample %d: after the DC blocker old %g, core %d\n", c, s, o.ay.left * 32768.0f, dl);
      return 0;
    }
    (*samples)++;
  }
  return 1;
}

// The set-up: upstream's float step (clock / (rate x 64)) x 2^19, truncated, against the core's clock x 8192 / rate.
// Every clock ChipNomad offers (project_ay.cpp's presets) must agree at the rates the machine uses; the rest
// is counted (a clock where they differ runs 1/65536 of a tick a sample apart: a slow phase drift, no more).
static int ticks_sweep(void) {
  static const unsigned presets[] = {750000, 1000000, 1750000, 1773400, 2000000};
  static const int rates[] = {22050, 44100, 48000};
  int bad = 0;
  for (int r = 0; r < 3; r++) {
    for (int i = 0; i < 5; i++) {
      float step = (float)presets[i] / (rates[r] * 8 * 8);
      unsigned f = (unsigned)(step * (float)(8 * 65536)), n = (unsigned)((unsigned long long)presets[i] * 8192u / rates[r]);
      if (f != n) { printf("ticks: preset %u at %d Hz: float %u, core %u\n", presets[i], rates[r], f, n); bad++; }
    }
    long off = 0;
    for (unsigned c = 500000; c <= 4000000; c++) {
      float step = (float)c / (rates[r] * 8 * 8);
      off += (unsigned)(step * (float)(8 * 65536)) != (unsigned)((unsigned long long)c * 8192u / rates[r]);
    }
    printf("ticks at %d Hz: every preset the same; %ld of 3,500,001 clocks from 0.5 to 4 MHz 1/65536 tick apart\n", rates[r], off);
  }
  return bad == 0;
}

int main(int argc, char** argv) {
  broke = argc > 1 && !strcmp(argv[1], "--break");
  if (!broke && !ticks_sweep()) { printf("ayumi check: FAILED\n"); return 1; }
  long samples = 0;
  int cases = 3000;
  for (int c = 0; c < cases; c++)
    if (!one_case(c, &samples)) {
      printf(broke ? "ayumi check: PASS (--break caught)\n" : "ayumi check: FAILED\n");
      return broke ? 0 : 1;
    }
  if (broke) { printf("ayumi check: FAILED -- --break not caught\n"); return 1; }
  printf("ayumi check: %d chips, %ld samples, every one the same as the cart's ayumi (out and after DC at 22050)\n", cases, samples);
  return 0;
}
