/* The SFX device's channel owners and register images (zm_vgm_own.h). Our own code. */
#include "zm_vgm_own.h"

#include "zm_mem.h"

void zm_img_reset(zm_chip_img *m) {
    memset(m, 0, sizeof *m);
    for (uint32_t r = 0; r < 3; r++) m->ym[0][0xB4 + r] = m->ym[1][0xB4 + r] = 0xC0; /* the power-on pans */
    for (uint32_t c = 0; c < 4; c++) m->psg.att[c] = 15;
}

uint32_t zm_ym_owner(uint32_t port, uint32_t reg, uint32_t val) {
    if (reg == 0x28) return port || (val & 3u) == 3u ? ZM_OWNER_NOBODY : (val & 3u) + (val & 4u ? 3u : 0u);
    if (reg == 0x2A || reg == 0x2B) return port ? ZM_OWNER_NOBODY : 5u;
    if (reg < 0x30) return port ? ZM_OWNER_NOBODY : ZM_OWNER_TUNE;
    if (reg >= 0xA8 && reg < 0xB0) return port ? ZM_OWNER_NOBODY : 2u;
    if (reg >= 0xB8 || (reg & 3u) == 3u) return ZM_OWNER_NOBODY;
    return port * 3u + (reg & 3u);
}

void zm_psg_mirror(zm_psg_img *m, uint32_t byte) {
    if (byte & 0x80u) m->latch = byte >> 4 & 7u;
    uint32_t c = m->latch >> 1;
    if (m->latch & 1u) m->att[c] = byte & 15u;
    else if (c < 3) m->period[c] = byte & 0x80u ? (m->period[c] & 0x3F0u) | (byte & 15u) : (m->period[c] & 15u) | (byte & 0x3Fu) << 4;
    else m->noise = byte & 7u;
}

void zm_psg_put(sn76489 *p, const zm_psg_img *m, uint32_t c) {
    uint32_t keep = p->latch;
    if (c < 3) {
        sn76489_write(p, 0x80u | c << 5 | (m->period[c] & 15u));
        sn76489_write(p, m->period[c] >> 4 & 0x3Fu);
    } else {
        sn76489_write(p, 0xE0u | m->noise);
    }
    sn76489_write(p, 0x90u | c << 5 | m->att[c]);
    p->latch = keep;
}

void zm_psg_mute(sn76489 *p, uint32_t c) {
    uint32_t keep = p->latch;
    sn76489_write(p, 0x90u | c << 5 | 15u);
    p->latch = keep;
}

void zm_ym_key(ym2612 *y, uint32_t ch, uint32_t slots) { ym2612_write(y, 0, 0x28, slots << 4 | (ch < 3 ? ch : ch + 1u)); }

void zm_ym_put(ym2612 *y, const zm_chip_img *m, uint32_t ch) {
    uint32_t port = ch / 3u, r = ch % 3u, keep = y->latch_hi[port];
    for (uint32_t b = 0x30; b < 0xA0; b += 4) ym2612_write(y, port, b + r, m->ym[port][b + r]);
    ym2612_write(y, port, 0xB0 + r, m->ym[port][0xB0 + r]);
    ym2612_write(y, port, 0xB4 + r, m->ym[port][0xB4 + r]);
    ym2612_write(y, port, 0xA4 + r, m->ym[port][0xA4 + r]);
    ym2612_write(y, port, 0xA0 + r, m->ym[port][0xA0 + r]);
    y->latch_hi[port] = keep;
    if (ch == 5) ym2612_write(y, 0, 0x2B, m->ym[0][0x2B]);
    zm_ym_key(y, ch, m->key[ch]);
}
