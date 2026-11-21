/* The YM2612's registers (ym2612.h), from the YM2608 application manual's FM register map and the Sega
 * Genesis Software Manual's YM2612 chapter: 0x22 LFO, 0x27 channel 3 mode, 0x28 key on/off, 0x2A/0x2B
 * the DAC, 0x30-0x9E the operators (offset +0/+4/+8/+C = S1/S3/S2/S4), 0xA0-0xAE frequencies (the high
 * byte latched until the low one is written), 0xB0-0xB6 algorithm, feedback, pans and LFO
 * sensitivities. Our own code. */
#include "ym2612.h"
#include "ym2612_tables.h"

#include <string.h>

void ym2612_reset(ym2612 *y, uint32_t div) {
    memset(y, 0, sizeof *y);
    y->div = div == 1 ? 1 : 2;
    y->gain = 256;
    y->am = 126;
    for (uint32_t c = 0; c < 6; c++) {
        y->ch[c].pan = 3;
        for (uint32_t k = 0; k < 4; k++) {
            ym_op *o = &y->ch[c].op[k];
            o->att = 0x3FF;
            o->state = YM_RELEASE;
            ym_op_rates(o);
        }
    }
}

/* The key code: block x 4 + fnum bit 10 x 2 + the "N3" bit of bits 10..7 (YM2608 manual). */
static uint32_t keycode(uint32_t fnum, uint32_t block) {
    uint32_t f11 = fnum >> 10 & 1u, f10 = fnum >> 9 & 1u, f9 = fnum >> 8 & 1u, f8 = fnum >> 7 & 1u;
    uint32_t n3 = (f11 & (f10 | f9 | f8)) | ((f11 ^ 1u) & f10 & f9 & f8);
    return block << 2 | f11 << 1 | n3;
}

/* Operator k's pitch from its channel's frequency, or channel 3's special ones (op 4 keeps the channel's). */
static void refresh(ym2612 *y, uint32_t ci) {
    ym_ch *c = &y->ch[ci];
    static const int8_t SPECIAL[4] = {1, 0, 2, -1}; /* slot S1 -> A9, S3 -> A8, S2 -> AA, S4 the channel's */
    for (uint32_t k = 0; k < 4; k++) {
        ym_op *o = &c->op[k];
        int own = ci == 2 && y->ch3_mode && SPECIAL[k] >= 0;
        uint32_t i = own ? (uint32_t)SPECIAL[k] : 0;
        o->fnum = own ? y->fnum3[i] : c->fnum;
        o->block = own ? y->block3[i] : c->block;
        o->kc = keycode(o->fnum, o->block);
        ym_op_rates(o);
        ym_op_pitch(y, c, o);
    }
}

static void op_write(ym2612 *y, ym_ch *c, ym_op *o, uint32_t reg, uint32_t v) {
    switch (reg & 0xF0u) {
    case 0x30: o->dt = v >> 4 & 7u, o->mul = v & 15u; break;
    case 0x40: o->tl3 = (uint16_t)((v & 0x7Fu) << 3); return;
    case 0x50: o->ks = v >> 6, o->ar = v & 31u; break;
    case 0x60: o->am_on = v >> 7, o->d1r = v & 31u; break;
    case 0x70: o->d2r = v & 31u; break;
    case 0x80: {
        uint32_t s = v >> 4;
        o->sl = (uint16_t)((s == 15 ? 31u : s) << 5);
        o->rr = v & 15u;
        break;
    }
    case 0x90: o->ssg = v & 15u; return;
    default: return;
    }
    ym_op_rates(o);
    ym_op_pitch(y, c, o);
}

static void global_write(ym2612 *y, uint32_t reg, uint32_t v) {
    if (reg == 0x22) {
        y->lfo_on = v >> 3 & 1u;
        y->lfo_inc = YM_LFO_INC[v & 7u] * y->div;
        if (!y->lfo_on) y->lfo_cnt = y->lfo_pos = 0, y->am = 126;
        for (uint32_t c = 0; c < 6; c++) ym_ch_pm(y, &y->ch[c]);
    } else if (reg == 0x27) {
        uint32_t m = (v >> 6) != 0;
        if (m != y->ch3_mode) y->ch3_mode = m, refresh(y, 2);
    } else if (reg == 0x28) {
        static const int8_t CH[8] = {0, 1, 2, -1, 3, 4, 5, -1};
        int ci = CH[v & 7u];
        if (ci < 0) return;
        ym_ch *c = &y->ch[ci];
        ym_key(&c->op[0], v >> 4 & 1u); /* bit 4 op1 (S1), 5 op2 (S2), 6 op3 (S3), 7 op4 (S4) */
        ym_key(&c->op[2], v >> 5 & 1u);
        ym_key(&c->op[1], v >> 6 & 1u);
        ym_key(&c->op[3], v >> 7 & 1u);
    } else if (reg == 0x2A) {
        y->dac = ((int32_t)(v & 0xFFu) - 128) << 6;
    } else if (reg == 0x2B) {
        y->dac_on = v >> 7;
    }
}

static void freq_write(ym2612 *y, uint32_t port, uint32_t reg, uint32_t v) {
    uint32_t r = reg & 3u;
    if (r == 3) return;
    uint32_t ci = port * 3u + r;
    ym_ch *c = &y->ch[ci];
    switch (reg & 0xFCu) {
    case 0xA4: y->latch_hi[port] = v & 0x3Fu; return;
    case 0xA0:
        c->fnum = (y->latch_hi[port] & 7u) << 8 | v;
        c->block = y->latch_hi[port] >> 3 & 7u;
        refresh(y, ci);
        return;
    case 0xAC: if (!port) y->latch3_hi = v & 0x3Fu; return;
    case 0xA8:
        if (port) return;
        y->fnum3[r] = (y->latch3_hi & 7u) << 8 | v;
        y->block3[r] = y->latch3_hi >> 3 & 7u;
        if (y->ch3_mode) refresh(y, 2);
        return;
    case 0xB0: c->fb = v >> 3 & 7u, c->alg = v & 7u; return;
    case 0xB4: c->pan = (uint8_t)(v >> 6), c->ams = v >> 4 & 3u, c->pms = v & 7u, ym_ch_pm(y, c); return;
    default: return;
    }
}

void ym2612_write(ym2612 *y, uint32_t port, uint32_t reg, uint32_t val) {
    port &= 1u, reg &= 0xFFu, val &= 0xFFu;
    if (reg < 0x30) {
        if (!port) global_write(y, reg, val);
        return;
    }
    if (reg >= 0xA0) {
        freq_write(y, port, reg, val);
        return;
    }
    uint32_t r = reg & 3u;
    if (r == 3) return;
    ym_ch *c = &y->ch[port * 3u + r];
    op_write(y, c, &c->op[reg >> 2 & 3u], reg, val);
}
