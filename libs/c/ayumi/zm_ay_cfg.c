/* zm_ay's set-up, register writes and envelope (zm_ay.h): integer tables only, so every CPU that runs the
 * chip computes the same state from the same writes (no sqrtf, no float clock: BARD has no FPU). */
#include "zm_ay.h"
#include "zm_ay_env.h"

/* upstream's DAC tables in Q15 (round(x * 32767)), two entries a 4-bit level as upstream */
static const int AY_dac[32] = {
  0, 0, 327, 327, 473, 473, 690, 690, 1006, 1006, 1492, 1492, 2113, 2113, 3518, 3518,
  4148, 4148, 6717, 6717, 9575, 9575, 12217, 12217, 16139, 16139, 20818, 20818, 26396, 26396, 32767, 32767
};
static const int YM_dac[32] = {
  0, 0, 152, 253, 359, 457, 557, 656, 798, 973, 1149, 1323, 1590, 1911, 2230, 2549,
  3031, 3640, 4251, 4865, 5789, 6932, 8073, 9211, 10935, 13121, 15315, 17512, 20813, 24837, 28832, 32767
};

/* (int)(sqrtf(k / 200.0f) * 32768 + 0.5f), k = 0..200: equal to what upstream's ayumi_set_pan computes in float
 * for every pan ChipNomad's stereo modes make (0.5 -/+ separation / 200), both sides (zm_ay_check.c). */
static const unsigned short EQP[ZM_AY_PAN_STEPS + 1] = {
  0, 2317, 3277, 4013, 4634, 5181, 5676, 6130, 6554, 6951, 7327, 7685, 8026, 8354, 8670, 8974, 9268, 9553, 9830, 10100,
  10362, 10618, 10868, 11112, 11351, 11585, 11815, 12040, 12261, 12478, 12691, 12901, 13107, 13310, 13511, 13708, 13902,
  14094, 14283, 14470, 14654, 14836, 15016, 15194, 15370, 15543, 15715, 15885, 16053, 16219, 16384, 16547, 16708, 16868,
  17027, 17184, 17339, 17493, 17646, 17798, 17948, 18097, 18244, 18391, 18536, 18681, 18824, 18966, 19107, 19247, 19386,
  19524, 19661, 19797, 19932, 20066, 20200, 20332, 20464, 20594, 20724, 20853, 20982, 21109, 21236, 21362, 21487, 21612,
  21736, 21859, 21981, 22103, 22224, 22345, 22465, 22584, 22702, 22820, 22938, 23054, 23170, 23286, 23401, 23515, 23629,
  23743, 23855, 23968, 24079, 24191, 24301, 24412, 24521, 24631, 24739, 24848, 24955, 25063, 25170, 25276, 25382, 25488,
  25593, 25697, 25802, 25905, 26009, 26112, 26214, 26317, 26418, 26520, 26621, 26721, 26822, 26922, 27021, 27120, 27219,
  27318, 27416, 27513, 27611, 27708, 27805, 27901, 27997, 28093, 28188, 28283, 28378, 28472, 28566, 28660, 28754, 28847,
  28940, 29033, 29125, 29217, 29309, 29400, 29491, 29582, 29673, 29763, 29853, 29943, 30032, 30122, 30211, 30299, 30388,
  30476, 30564, 30652, 30739, 30826, 30913, 31000, 31086, 31173, 31259, 31344, 31430, 31515, 31600, 31685, 31770, 31854,
  31938, 32022, 32106, 32189, 32273, 32356, 32439, 32521, 32604, 32686, 32768
};

enum { SLIDE_DOWN, SLIDE_UP, HOLD_TOP, HOLD_BOTTOM };
static const unsigned char Envelopes[16][2] = {
  {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, HOLD_BOTTOM},
  {SLIDE_UP, HOLD_BOTTOM}, {SLIDE_UP, HOLD_BOTTOM}, {SLIDE_UP, HOLD_BOTTOM}, {SLIDE_UP, HOLD_BOTTOM},
  {SLIDE_DOWN, SLIDE_DOWN}, {SLIDE_DOWN, HOLD_BOTTOM}, {SLIDE_DOWN, SLIDE_UP}, {SLIDE_DOWN, HOLD_TOP},
  {SLIDE_UP, SLIDE_UP}, {SLIDE_UP, HOLD_TOP}, {SLIDE_UP, SLIDE_DOWN}, {SLIDE_UP, HOLD_BOTTOM}
};

static int env_action(const struct zm_ay* ay) { return Envelopes[ay->env_shape][ay->env_segment]; }

int zm_ay_env_holds(const struct zm_ay* ay) { int a = env_action(ay); return a == HOLD_TOP || a == HOLD_BOTTOM; }

void zm_ay_env_reset(struct zm_ay* ay) {
  int a = env_action(ay);
  ay->env = (a == SLIDE_DOWN || a == HOLD_TOP) ? 31 : 0;
}

void zm_ay_env_advance(struct zm_ay* ay, int k) {
  while (k > 0) {
    int a = env_action(ay);
    if (a == HOLD_TOP || a == HOLD_BOTTOM) return;
    int room = a == SLIDE_UP ? 32 - ay->env : ay->env + 1;   /* wraps until it leaves 0..31 */
    int s = k < room ? k : room;
    ay->env += a == SLIDE_UP ? s : -s;
    k -= s;
    if (ay->env < 0 || ay->env > 31) { ay->env_segment ^= 1; zm_ay_env_reset(ay); }
  }
}

void zm_ay_init(struct zm_ay* ay, int is_ym, unsigned clock, unsigned rate) {
  unsigned char* p = (unsigned char*)ay;
  for (unsigned i = 0; i < sizeof *ay; i++) p[i] = 0;
  ay->rate = rate ? rate : 1;
  ay->dc_shift = 8;                                  /* ~14 Hz at 22050; one more a doubling of the rate */
  for (unsigned r = ay->rate; r >= 33075 && ay->dc_shift < 15; r >>= 1) ay->dc_shift++;
  for (unsigned r = ay->rate; r < 16538 && ay->dc_shift > 1; r <<= 1) ay->dc_shift--;
  zm_ay_set_type(ay, is_ym);
  ay->noise = 1;
  zm_ay_set_envelope(ay, 1);
  for (int i = 0; i < ZM_AY_CHANNELS; i++) { zm_ay_set_tone(ay, i, 1); zm_ay_set_pan(ay, i, 100, 1); }
  ay->regs[7] = 0x3f;                                /* as ChipNomad's SoundChipAY starts it */
  zm_ay_set_clock(ay, clock);
}

/* 16.16 ticks (clock / 8) a sample: upstream's float step x 8 x 65536, the same integer for every clock up to
 * 3.5 MHz at 22050, 44100 and 48000 (zm_ay_check.c) */
void zm_ay_set_clock(struct zm_ay* ay, unsigned clock) {
  ay->clock = clock;
  ay->ticks_q16 = (unsigned)((unsigned long long)clock * 8192u / ay->rate);
}

void zm_ay_set_type(struct zm_ay* ay, int is_ym) { ay->dac = is_ym ? YM_dac : AY_dac; }

int zm_ay_pan_q15(int k, int is_eqp) {
  k = k < 0 ? 0 : k > ZM_AY_PAN_STEPS ? ZM_AY_PAN_STEPS : k;
  return is_eqp ? EQP[k] : (k * 32768 + ZM_AY_PAN_STEPS / 2) / ZM_AY_PAN_STEPS;
}

void zm_ay_set_pan(struct zm_ay* ay, int i, int k, int is_eqp) {
  zm_ay_set_pan_q15(ay, i, zm_ay_pan_q15(ZM_AY_PAN_STEPS - k, is_eqp), zm_ay_pan_q15(k, is_eqp));
}

void zm_ay_set_pan_q15(struct zm_ay* ay, int i, int left, int right) { ay->pan_l[i] = left; ay->pan_r[i] = right; }

void zm_ay_set_tone(struct zm_ay* ay, int i, int period) { period &= 0xfff; ay->ch[i].period = (period == 0) | period; }
void zm_ay_set_noise(struct zm_ay* ay, int period) { period &= 0x1f; ay->noise_period = (period == 0) | period; }
void zm_ay_set_mixer(struct zm_ay* ay, int i, int t_off, int n_off, int e_on) {
  ay->ch[i].t_off = t_off & 1;
  ay->ch[i].n_off = n_off & 1;
  ay->ch[i].e_on = e_on;
}
void zm_ay_set_volume(struct zm_ay* ay, int i, int volume) { ay->ch[i].volume = volume & 0xf; }
void zm_ay_set_envelope(struct zm_ay* ay, int period) { period &= 0xffff; ay->env_period = (period == 0) | period; }
void zm_ay_set_envelope_shape(struct zm_ay* ay, int shape) {
  ay->env_shape = shape & 0xf;
  ay->env_counter = 0;
  ay->env_segment = 0;
  zm_ay_env_reset(ay);
}
void zm_ay_set_timer(struct zm_ay* ay, int (*timer)(void* ud), void* ud) { ay->timer = timer; ay->timer_ud = ud; }

/* ChipNomad's SoundChipAY::setRegister: a register as the chip takes it (13 re-triggers the envelope). */
void zm_ay_write(struct zm_ay* ay, int reg, int value) {
  if (reg < 0 || reg > 13) return;
  unsigned char* r = ay->regs;
  r[reg] = (unsigned char)value;
  if (reg <= 5) {
    zm_ay_set_tone(ay, reg >> 1, r[reg | 1] << 8 | r[reg & ~1]);
  } else if (reg == 6) {
    zm_ay_set_noise(ay, r[6]);
  } else if (reg <= 10) {
    for (int i = 0; i < ZM_AY_CHANNELS; i++) {
      zm_ay_set_mixer(ay, i, r[7] >> i & 1, r[7] >> (3 + i) & 1, r[8 + i] >> 4);
      zm_ay_set_volume(ay, i, r[8 + i] & 0xf);
    }
  } else if (reg <= 12) {
    zm_ay_set_envelope(ay, r[12] << 8 | r[11]);
  } else {
    zm_ay_set_envelope_shape(ay, r[13]);
  }
}
