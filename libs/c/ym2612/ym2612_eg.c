/* The YM2612's envelope generator and pitch (ym2612.h). Written from the YM2608 application manual
 * (rates, key scaling, sustain level, detune) and Nemesis's hardware notes on the YM2612 (SpritesMind,
 * "New Documentation: An authoritative reference on the YM2612"): the EG ticks once every 3 chip
 * samples; a rate R updates every 2^shift ticks with an 8-step increment pattern; attack moves by
 * (~att x inc) >> 4, the others add inc; SSG-EG steps 4x below 0x200 and repeats, alternates or holds
 * there. Our own code. */
#include "ym2612.h"
#include "ym2612_tables.h"

/* Effective rates: 2 x R + the key-scaling rate (key code >> (3 - KS)), at most 63; R 0 stays 0. */
static uint8_t eff(uint32_t r5, uint32_t ksr) {
    uint32_t r = r5 ? 2 * r5 + ksr : 0;
    return (uint8_t)(r > 63 ? 63 : r);
}

/* The current state's rate, its update mask (2^shift - 1) and shift: kept so the EG tick's common case
 * (no update due) is one AND. Redone whenever the state or the rates change. */
static void eg_cache(ym_op *o) {
    uint32_t r = o->rate[o->state], sh = YM_EG_SHIFT[r];
    o->eg_rate = (uint8_t)r;
    o->eg_shift = (uint8_t)sh;
    o->eg_mask = (uint16_t)((1u << sh) - 1u);
}

static void set_state(ym_op *o, uint8_t s) {
    o->state = s;
    eg_cache(o);
}

void ym_op_rates(ym_op *o) {
    uint32_t ksr = o->kc >> (3 - o->ks);
    o->rate[YM_ATTACK] = eff(o->ar, ksr);
    o->rate[YM_DECAY] = eff(o->d1r, ksr);
    o->rate[YM_SUSTAIN] = eff(o->d2r, ksr);
    o->rate[YM_RELEASE] = eff(2u * o->rr + 1u, ksr);
    eg_cache(o);
}

/* The phase increment: fnum moved by the channel's LFO PM, (fnum << block) >> 1, detuned, times the
 * multiple (0 is a half), 20 bits, then x div for our render rate. */
void ym_op_pitch(const ym2612 *y, const ym_ch *c, ym_op *o) {
    int32_t dev = ((int32_t)o->fnum * c->pm) >> 16;
    uint32_t f = (uint32_t)((int32_t)o->fnum + dev) & 0xFFFu;
    uint32_t base = (f << o->block) >> 1;
    uint32_t d = YM_DT[(o->dt & 3u) * 32u + o->kc];
    base = (o->dt & 4u ? base - d : base + d) & 0x1FFFFu;
    uint32_t inc = o->mul ? base * o->mul : base >> 1;
    o->inc = (inc & 0xFFFFFu) * y->div;
}

static int ssg_inverted(const ym_op *o) { return ((o->ssg >> 2) ^ o->ssg_inv) & 1u; }

void ym_key(ym_op *o, uint32_t on) {
    if (on && !o->key) {
        o->phase = 0;
        o->ssg_inv = 0;
        set_state(o, YM_ATTACK);
        if (o->rate[YM_ATTACK] >= 62) {
            o->att = 0;
            set_state(o, YM_DECAY);
        }
    } else if (!on && o->key) {
        if ((o->ssg & 8u) && ssg_inverted(o)) o->att = (0x200 - o->att) & 0x3FF; /* release from what is heard */
        o->ssg_inv = 0;
        set_state(o, YM_RELEASE);
    }
    o->key = (uint8_t)(on != 0);
    ym_op_eatt(o);
}

/* SSG-EG at 0x200 and past (keyed, not attacking): hold (bit 0), alternate (bit 1) or repeat. Bit 1 of
 * ssg_inv marks a hold already taken. */
static void ssg_edge(ym_op *o) {
    if (o->ssg & 1u) {
        if (o->ssg_inv & 2u) return;
        if (o->ssg & 2u) o->ssg_inv ^= 1u;
        o->ssg_inv |= 2u;
        o->att = ssg_inverted(o) ? 0x200 : 0x3FF;
        return;
    }
    if (o->ssg & 2u) o->ssg_inv ^= 1u;
    else o->phase = 0;
    set_state(o, YM_ATTACK);
}

/* The attenuation the operator is heard at before the LFO's AM: SSG-EG's inversion, + TL, at most 0x3FF.
 * Kept in eatt, redone whenever att, TL or the SSG state moves (the render reads it every sample). */
void ym_op_eatt(ym_op *o) {
    uint32_t a = (uint32_t)o->att;
    if ((o->ssg & 8u) && ssg_inverted(o)) a = (0x200u - a) & 0x3FFu;
    a += o->tl3;
    o->eatt = (uint16_t)(a > 0x3FFu ? 0x3FFu : a);
}

static void eg_advance(ym_op *o, uint32_t r, int32_t inc) {
    if (o->state == YM_ATTACK) {
        if (r >= 62) o->att = 0;
        else if (inc) o->att += (~o->att * inc) >> 4;
        if (o->att <= 0) {
            o->att = 0;
            set_state(o, YM_DECAY);
        }
        return;
    }
    if (o->ssg & 8u) { /* 4x below 0x200; past it a held or released SSG envelope is done */
        if (o->att >= 0x200) {
            if (o->state == YM_RELEASE) o->att = 0x3FF;
            return;
        }
        inc = (o->ssg_inv & 2u) ? 0 : inc * 4;
    }
    o->att += inc;
    if (o->att > 0x3FF) o->att = 0x3FF;
    if (o->state == YM_DECAY && o->att >= o->sl) set_state(o, YM_SUSTAIN);
}

/* One EG tick of one operator; 0 when it is silent for good (released to 0x3FF). */
static inline uint32_t eg_step(ym_op *o, uint32_t cnt) {
    if (o->state == YM_RELEASE && o->att >= 0x3FF) return 0;
    if ((o->ssg & 8u) && o->key && o->state != YM_ATTACK && o->att >= 0x200) ssg_edge(o), ym_op_eatt(o);
    if (cnt & o->eg_mask) return 1;
    uint32_t r = o->eg_rate;
    int32_t inc = YM_EG_INC[YM_EG_ROW[r] * 8u + (cnt >> o->eg_shift & 7u)];
    eg_advance(o, r, inc);
    ym_op_eatt(o);
    return o->state != YM_RELEASE || o->att < 0x3FF;
}

void ym_eg_tick(ym2612 *y) {
    uint32_t cnt = ++y->eg_cnt;
    for (uint32_t c = 0; c < 6; c++) {
        ym_ch *ch = &y->ch[c];
        if (!ch->live) continue;
        uint32_t live = 0;
        for (uint32_t k = 0; k < 4; k++) live |= eg_step(&ch->op[k], cnt);
        ch->live = (uint8_t)live;
    }
}
