/* The SFX device's channel owners (zm_vgm_own.c): which channel a register write is for, and a writer's image
 * of the registers it set, to put back on the chips when a channel changes hands or the chips are reset. */
#ifndef ZM_VGM_OWN_H
#define ZM_VGM_OWN_H

#include "../sn76489/sn76489.h"
#include "../ym2612/ym2612.h"

#define ZM_OWNER_TUNE 6u   /* a global register (LFO, timers, channel 3's mode): always the tune's */
#define ZM_OWNER_NOBODY 7u /* no register there */

typedef struct {
    uint32_t period[3], att[4], noise, latch;
} zm_psg_img; /* an SN76489's registers as one writer set them */

typedef struct {
    uint8_t ym[2][256], key[6]; /* the YM2612's two ports; each channel's key-on slots (0x28's top nibble) */
    zm_psg_img psg;
} zm_chip_img;

void zm_img_reset(zm_chip_img *m); /* the chips' power-on values */
/* The FM channel (0..5) a YM2612 write is for: 0x28 by its value, the DAC (0x2A, 0x2B) FM 6's, channel 3's
 * special frequencies (0xA8-0xAE) FM 3's; ZM_OWNER_TUNE or ZM_OWNER_NOBODY. */
uint32_t zm_ym_owner(uint32_t port, uint32_t reg, uint32_t val);
void zm_psg_mirror(zm_psg_img *m, uint32_t byte); /* sn76489_write's register rules, on an image */
/* Channel c (0..2 a tone, 3 the noise) from the image / silenced; the chip's latch is left as it was. */
void zm_psg_put(sn76489 *p, const zm_psg_img *m, uint32_t c);
void zm_psg_mute(sn76489 *p, uint32_t c);
void zm_ym_key(ym2612 *y, uint32_t ch, uint32_t slots);
/* FM channel ch's registers from the image (operators, algorithm, pans, frequency; FM 6 its DAC switch too),
 * keyed as it was; the port's A4 latch is left as it was. */
void zm_ym_put(ym2612 *y, const zm_chip_img *m, uint32_t ch);

#endif
