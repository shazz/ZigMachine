/* The YM2612's operators, algorithms and output (ym2612.h). An operator is computed in the log domain
 * as the chip does: -log2 sin of the phase (plus the modulation, in sine-table steps: half the
 * modulator's 14-bit output), plus the attenuation x 4, through the exponent table to a 13-bit
 * magnitude and its sign. Operators run in the chip's order S1, S3, S2, S4, so where a later one
 * feeds an earlier one (S2 -> S3 in algorithms 0-2) the link is last sample's value. Op 1 feeds back
 * the mean of its last two outputs, scaled by FB. The LFO's AM triangle (0..126 units, by AMS >> 3/1/0)
 * and PM triangle (8 steps a quarter, by PMS) follow the YM2608 manual's depths. The DAC (0x2B bit 7)
 * replaces channel 6. Our own code: libs/c/ym2612/README.md. */
#include "ym2612.h"
#include "ym2612_tables.h"

/* At 832 (x 4 = 13 << 8) even the sine's loudest step (YM_LOGSIN[255] is 0) is below one unit: 0, exactly. */
static inline int32_t op_calc(const ym_op *o, int32_t mod, uint32_t att) {
    if (att >= 832u) return 0;
    uint32_t p = ((o->phase >> 10) + (uint32_t)mod) & 0x3FFu;
    uint32_t q = p & 0x100u ? ~p & 0xFFu : p & 0xFFu;
    uint32_t l = YM_LOGSIN[q] + (att << 2);
    if (l >= 13u << 8) return 0;
    int32_t v = (int32_t)(((uint32_t)YM_EXP[l & 0xFFu] << 2) >> (l >> 8));
    return p & 0x200u ? -v : v;
}

/* The attenuation heard: eatt (SSG-EG's inversion and TL, ym_op_eatt) + the LFO's AM; at most 0x3FF. */
static inline uint32_t op_att(const ym_op *o, uint32_t am) {
    if (!am || !o->am_on) return o->eatt;
    uint32_t a = o->eatt + am;
    return a > 0x3FFu ? 0x3FFu : a;
}

/* One sample of channel c: its output, 14-bit signed. */
static int32_t channel(ym_ch *c, uint32_t am_tri) {
    static const uint8_t AMS_SHIFT[4] = {8, 3, 1, 0};
    uint32_t am = am_tri >> AMS_SHIFT[c->ams];
    ym_op *s1 = &c->op[0], *s3 = &c->op[1], *s2 = &c->op[2], *s4 = &c->op[3];
    int32_t fbm = c->fb ? (c->fb1 + c->fb2) >> (10 - c->fb) : 0;
    int32_t o1 = op_calc(s1, fbm, op_att(s1, am)), o2, o3, o4, out;
    c->fb2 = c->fb1;
    c->fb1 = o1;
    switch (c->alg) {
    case 0: /* 1 -> 2 -> 3 -> 4 */
        o3 = op_calc(s3, c->mem >> 1, op_att(s3, am));
        o2 = op_calc(s2, o1 >> 1, op_att(s2, am));
        c->mem = o2;
        out = op_calc(s4, o3 >> 1, op_att(s4, am));
        break;
    case 1: /* (1 + 2) -> 3 -> 4 */
        o3 = op_calc(s3, (o1 + c->mem) >> 1, op_att(s3, am));
        c->mem = op_calc(s2, 0, op_att(s2, am));
        out = op_calc(s4, o3 >> 1, op_att(s4, am));
        break;
    case 2: /* (1 + (2 -> 3)) -> 4 */
        o3 = op_calc(s3, c->mem >> 1, op_att(s3, am));
        c->mem = op_calc(s2, 0, op_att(s2, am));
        out = op_calc(s4, (o1 + o3) >> 1, op_att(s4, am));
        break;
    case 3: /* ((1 -> 2) + 3) -> 4 */
        o3 = op_calc(s3, 0, op_att(s3, am));
        o2 = op_calc(s2, o1 >> 1, op_att(s2, am));
        out = op_calc(s4, (o2 + o3) >> 1, op_att(s4, am));
        break;
    case 4: /* (1 -> 2) + (3 -> 4) */
        o3 = op_calc(s3, 0, op_att(s3, am));
        o2 = op_calc(s2, o1 >> 1, op_att(s2, am));
        out = o2 + op_calc(s4, o3 >> 1, op_att(s4, am));
        break;
    case 5: /* 1 -> 2, 3, 4 */
        o3 = op_calc(s3, o1 >> 1, op_att(s3, am));
        o2 = op_calc(s2, o1 >> 1, op_att(s2, am));
        out = o2 + o3 + op_calc(s4, o1 >> 1, op_att(s4, am));
        break;
    case 6: /* (1 -> 2) + 3 + 4 */
        o3 = op_calc(s3, 0, op_att(s3, am));
        o2 = op_calc(s2, o1 >> 1, op_att(s2, am));
        out = o2 + o3 + op_calc(s4, 0, op_att(s4, am));
        break;
    default: /* 1 + 2 + 3 + 4 */
        o3 = op_calc(s3, 0, op_att(s3, am));
        o2 = op_calc(s2, 0, op_att(s2, am));
        o4 = op_calc(s4, 0, op_att(s4, am));
        out = o1 + o2 + o3 + o4;
        break;
    }
    for (uint32_t k = 0; k < 4; k++) c->op[k].phase += c->op[k].inc;
    return out > 8191 ? 8191 : out < -8191 ? -8191 : out; /* the 14-bit accumulator */
}

/* The LFO's PM step now: 0..7 up a quarter, back down, then the same negative. */
static int32_t pm_step(uint32_t cnt) {
    uint32_t s = cnt >> 2, q = s & 7u;
    if (s & 8u) q = 7u - q;
    return s & 16u ? -(int32_t)q : (int32_t)q;
}

/* Channel c's PM at the LFO's step now (0 with the LFO off or PMS 0); its pitch redone on a change. */
void ym_ch_pm(ym2612 *y, ym_ch *c) {
    int32_t pm = y->lfo_on && c->pms ? (int32_t)YM_PM_DEPTH[c->pms] * pm_step(y->lfo_cnt) : 0;
    if (pm == c->pm) return;
    c->pm = pm;
    for (uint32_t k = 0; k < 4; k++) ym_op_pitch(y, c, &c->op[k]);
}

static void lfo_advance(ym2612 *y) {
    if (!y->lfo_on) return;
    uint32_t was = y->lfo_cnt;
    y->lfo_pos += y->lfo_inc;
    y->lfo_cnt = y->lfo_pos >> 16 & 127u;
    if (y->lfo_cnt == was) return;
    uint32_t t = y->lfo_cnt & 63u;
    y->am = (y->lfo_cnt & 64u ? t : 63u - t) << 1;
    for (uint32_t ci = 0; ci < 6; ci++) ym_ch_pm(y, &y->ch[ci]);
}

static int16_t clamp16(int32_t v) { return (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v); }

void ym2612_render(ym2612 *y, int16_t *lr, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        int32_t l = 0, r = 0;
        uint32_t am = y->lfo_on ? y->am : 0;
        for (uint32_t ci = 0; ci < 6; ci++) {
            ym_ch *c = &y->ch[ci];
            int32_t v;
            if (ci == 5 && y->dac_on) v = y->dac;
            else if (!c->live) c->fb1 = c->fb2 = c->mem = 0, v = 0;
            else v = channel(c, am);
            if (c->pan & 2u) l += v;
            if (c->pan & 1u) r += v;
        }
        lr[2 * i] = clamp16((l * y->gain) >> 8);
        lr[2 * i + 1] = clamp16((r * y->gain) >> 8);
        for (y->eg_acc += y->div; y->eg_acc >= 3; y->eg_acc -= 3) ym_eg_tick(y);
        lfo_advance(y);
    }
}
