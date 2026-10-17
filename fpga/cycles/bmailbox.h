/* The board firmware's debug mailbox (bmailbox.c): what the ARM needs to take a
 * screenshot from U-Boot (fpga/tools/board_shot.py), at a FIXED address: the last
 * 256 bytes of the cart window, CPU 0x41ffff00 = PS DDR 0x05ffff00. The link
 * (cycles/board.mk) keeps the stack below it.
 *
 * Words (u32, little-endian; addresses are CPU bus addresses, DDR = addr -
 * cpu_base + ddr_base):
 *   0 magic 'ZMMB'   1 version         2 fb0          3 fb1
 *   4 presented: the picture (0/1) of the last PRESENT, shown from the next VBL
 *   5 frames finished                   6 pfb: the machine's PFB (what scene_hash hashes)
 *   7 pfb width   8 pfb height (pixels; RGBA bytes)
 *   9 picture width  10 picture height (pixels; {0,B,G,R} words: bytes R,G,B,0)
 *  11 cpu_base  12 ddr_base
 *  13 freeze: the ARM writes 1; the firmware stops after its next whole frame
 *  14 frozen: the frame it stopped on (0 while running); clear `freeze` to resume
 *  15 front: the video's FRONT bit when frozen
 * Version 2: mb_init zeroes the whole page (ZM_MB_PAGE_WORDS), and its tail is the players':
 *  32..39 'ZMAU' and the audio core's counters (cycles/baudio.c)
 *  40..63 the music block, 'ZMSI': who plays what, and its cost (cycles/bsndinfo.h) */
#ifndef ZM_BMAILBOX_H
#define ZM_BMAILBOX_H

#include <stdint.h>

#define ZM_MB_ADDR 0x41ffff00u
#define ZM_MB_MAGIC 0x424d4d5au /* "ZMMB" */
#define ZM_MB_VERSION 2u /* glass/src/map_cart.zig MB_VERSION_SND_INFO */
#define ZM_MB_PAGE_WORDS 64u
/* The two pictures at fixed addresses (DDR 0x04c00000, 0x04d00000): above the
 * firmware image (< 12 MiB, checked by board.mk), below the data at 0x41000000. */
#define ZM_FB0_ADDR 0x40c00000u
#define ZM_FB1_ADDR 0x40d00000u

enum {
    MB_MAGIC, MB_VERSION, MB_FB0, MB_FB1, MB_PRESENTED, MB_FRAMES, MB_PFB, MB_PFB_W, MB_PFB_H,
    MB_PIC_W, MB_PIC_H, MB_CPU_BASE, MB_DDR_BASE, MB_FREEZE, MB_FROZEN, MB_FRONT, MB_WORDS
};

void mb_init(uint32_t pfb, uint32_t pfb_w, uint32_t pfb_h);
/* Before PRESENT: the picture being completed is the back one. */
void mb_presenting(void);
/* After a whole frame: count it, and stop here while the ARM asks for a freeze. */
void mb_frame_done(uint32_t frames);

#endif
