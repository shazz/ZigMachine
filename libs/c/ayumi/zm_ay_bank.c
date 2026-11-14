/* The BARD queue's AY device (zm_ay_bank.h): integers only, no divide a sample. */
#include "zm_ay_bank.h"
#include "zm_ay.h"

static struct zm_ay chips[ZM_AY_BANK_CHIPS];
static int gain[ZM_AY_BANK_CHIPS];
static uint32_t on;

void zm_ay_bank_reset(void) { on = 0; }

uint32_t zm_ay_bank_on(void) { return on; }

static void configure(int c, uint32_t v) {
  if ((v & 0xFFFFFFu) < 8) { on &= ~(1u << c); return; }  /* no clock: the chip off */
  zm_ay_init(&chips[c], (v & ZM_AY_CFG_YM) != 0, v & 0xFFFFFFu, ZM_AY_BANK_RATE);
  gain[c] = 32768;
  on |= 1u << c;
}

static void stereo(int c, uint32_t v) {
  for (int i = 0; i < ZM_AY_CHANNELS; i++) zm_ay_set_pan(&chips[c], i, (int)(v >> (8 * i) & 0xFF), (v & ZM_AY_PAN_EQP) != 0);
}

int zm_ay_bank_write(uint32_t a, uint32_t value) {
  if (a >= ZM_AY_GAIN_BASE) {
    int c = (int)(a - ZM_AY_GAIN_BASE);
    if (c >= ZM_AY_BANK_CHIPS || !(on >> c & 1)) return 0;
    gain[c] = (int)(value & 0xFFFF);
    return 1;
  }
  int c = (int)(a >> 4), reg = (int)(a & 15);
  if (reg == ZM_AY_REG_CONFIG) { configure(c, value); return 1; }
  if (!(on >> c & 1)) return 0;
  if (reg == ZM_AY_REG_STEREO) stereo(c, value);
  else zm_ay_write(&chips[c], reg, (int)(value & 0xFF));
  return 1;
}

static int16_t clamp16(int x) { return (int16_t)(x > 32767 ? 32767 : x < -32768 ? -32768 : x); }

void zm_ay_bank_render(int16_t* stereo_out, uint32_t n) {
  for (uint32_t f = 0; f < n; f++) {
    int l = 0, r = 0;
    for (int c = 0; c < ZM_AY_BANK_CHIPS; c++) {
      if (!(on >> c & 1)) continue;
      int cl, cr;
      zm_ay_process(&chips[c]);
      zm_ay_remove_dc(&chips[c], &cl, &cr);
      l += (cl * gain[c]) >> 15;
      r += (cr * gain[c]) >> 15;
    }
    stereo_out[2 * f] = clamp16(l);
    stereo_out[2 * f + 1] = clamp16(r);
  }
}
