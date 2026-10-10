/* The board write-path diagnostic (bdiag.c). DDR addresses (PS view); the CPU sees
 * DDR d at 0x40000000 + d - 0x04000000. All inside the cart window, above the image. */
#ifndef ZM_BDIAG_H
#define ZM_BDIAG_H

#include <stdint.h>

#define DIAG_MAGIC 0x47414944u    /* "DIAG" at DIAG_CTL_DDR, the mode at +4 */
#define DIAG_CTL_DDR 0x05fffe00u  /* in the top 4 KiB the link keeps free (board.mk) */
#define DIAG_STORE_DDR 0x05f00000u /* mode 1: the CPU's stores */
#define DIAG_LOAD_DDR 0x05f00200u  /* mode 2: words the ARM wrote, the CPU checks */
#define DIAG_VBASE_DDR 0x05e00000u /* mode 3: the region; its PFB row 0 at + ZM_OFF_PFB = 0x05f01100 */
#define DIAG_PIC_DDR 0x05f80000u   /* mode 3: the picture (both buffers): row 0 */
#define DIAG_PROBE_DDR 0x05f80c00u /* mode 4: the read-path probe's 8 words */
#define DIAG_BG 0x55667788u        /* mode 3: REG_BACKGROUND */
#define DIAG_CFG_TAG 0xc0f0u       /* word +8: 0xc0f0000c sets the video's hp_cfg to c */

/* Runs the diagnostic and never returns if one was asked for; else 0. */
int diag_maybe(void);
/* hp_cfg from the control word's +8, if tagged (also for the cart). */
void diag_apply_cfg(void);

#endif
