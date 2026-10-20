/* Board write-path diagnostic (bdiag.h): run INSTEAD of the cart when the ARM has
 * put DIAG_MAGIC at DDR 0x05fffe00 and a mode at 0x05fffe04 before CTRL.RUN. The
 * same image runs the cart otherwise, so no rebuild between modes: clear CTRL.RUN,
 * change the mode, set CTRL.RUN.
 *
 *   1 CPU stores over HP0: 32 words (sw), 16 halfwords (sh), 16 bytes (sb)
 *   2 CPU loads over HP0: reads 32 words the ARM wrote, CART_BEAT = mismatch bitmask
 *   3 video DMA over HP1: one BG pass (the PFB row) and one MIX pass (a picture row)
 *   4 video DMA over HP1: one MIX pass from a PFB row the ARM wrote (a known varying pattern)
 * Word +8 = 0xc0f0000c (c = the video's hp_cfg: bit 0 UPSIZE, bit 1 W64) sets how the DMA
 * writes, for the cart too; anything else leaves the default 0 (4-byte beats, expanded). W64
 * needs HP1's AFI write channel 64-bit (WRCHAN_CTRL 0xf00) from boot, never switched 32 -> 64
 * after 32-bit traffic (decisions.md 2026-10-19).
 * Its bits 4-5 are the system's other A/B switches (bdiag.h DIAG_OPT_*).
 * CART_STATE = 0x44 | mode << 8 when done (0x43c00010), CART_BEAT = the mode's result. */
#include "bdiag.h"

#include <stdio.h>

#include "bboard.h"
#include "glass_cart.h"
#include "vboard.h"
#include "zm_memmap.h"

#define CPU(ddr) ((volatile uint32_t*)((ddr) - 0x04000000u + 0x40000000u))
#define CTL CPU(DIAG_CTL_DDR)

static uint32_t mode_1_stores(void) {
    volatile uint32_t* w = CPU(DIAG_STORE_DDR);
    for (uint32_t i = 0; i < 32; i++) w[i] = (i + 1) * 0x01010101u; /* 0x01010101, 0x02020202, ... */
    volatile uint16_t* h = (volatile uint16_t*)CPU(DIAG_STORE_DDR + 0x100);
    for (uint32_t i = 0; i < 16; i++) h[i] = (uint16_t)(0xA100u + i);
    volatile uint8_t* b = (volatile uint8_t*)CPU(DIAG_STORE_DDR + 0x140);
    for (uint32_t i = 0; i < 16; i++) b[i] = (uint8_t)(0xB0u + i);
    return 1;
}

static uint32_t mode_2_loads(void) {
    zmv_flush_dcache();
    volatile uint32_t* w = CPU(DIAG_LOAD_DDR);
    uint32_t bad = 0;
    for (uint32_t i = 0; i < 32; i++)
        if (w[i] != 0xC0DE0000u + i) bad |= 1u << i; /* the ARM wrote 0xc0de0000 + i */
    return bad;
}

/* Each wait publishes its number and the video STATUS it last saw in CART_BEAT
 * (0x5a00_0000 | n << 16 | status): a hang says which bit never came. */
static uint32_t g_wait;

static void wait_bits(uint32_t bits) {
    uint32_t n = ++g_wait, st;
    while (((st = zmv_status()) & bits) != bits) board_beat(0x5a000000u | (n << 16) | (st & 0xffffu));
    board_beat(0x5a000000u | (n << 16) | 0x8000u | (st & 0x7fffu));
}

static uint32_t mode_3_dma(void) {
    volatile uint32_t* r = CPU(DIAG_VBASE_DDR);
    ZMV_REG(VBASE) = (uint32_t)(uintptr_t)r;
    ZMV_REG(FB0) = (uint32_t)(uintptr_t)CPU(DIAG_PIC_DDR);
    ZMV_REG(FB1) = (uint32_t)(uintptr_t)CPU(DIAG_PIC_DDR);
    r[ZM_REG_BACKGROUND / 4] = DIAG_BG; /* reaches the compositor through the snoop, whatever DDR does */
    wait_bits(ZMV_BIT(READY) | ZMV_BIT(DRAINED));
    zmv_cmd(ZMV_BG, 0, 0, 0, 0, 0);
    wait_bits(ZMV_BIT(PAINTED));
    wait_bits(ZMV_BIT(READY));
    zmv_cmd(ZMV_MIX, 0, 0, 1, 1, 0);
    wait_bits(ZMV_BIT(PAINTED));
    wait_bits(ZMV_BIT(READY));
    return 3;
}

/* Mode 4: a MIX pass alone, from a PFB row the ARM wrote (32 distinct opaque grey words
 * 0xff{ii}{ii}{ii}, ii = i + 1): the picture row shows where each of the DMA's words lands. */
static uint32_t mode_4_mix(void) {
    ZMV_REG(VBASE) = (uint32_t)(uintptr_t)CPU(DIAG_VBASE_DDR);
    ZMV_REG(FB0) = (uint32_t)(uintptr_t)CPU(DIAG_PIC_DDR);
    ZMV_REG(FB1) = (uint32_t)(uintptr_t)CPU(DIAG_PIC_DDR);
    wait_bits(ZMV_BIT(READY) | ZMV_BIT(DRAINED));
    zmv_cmd(ZMV_MIX, 0, 0, 1, 1, 0);
    wait_bits(ZMV_BIT(PAINTED));
    wait_bits(ZMV_BIT(READY));
    /* The read path's probe (soc/zm_hp_probe.py): 8 CSR words, most significant first:
     * q1.hi q1.lo q0.hi q0.lo axi1.hi axi1.lo axi0.hi axi0.lo. */
#ifdef CSR_ZMV_HP_PROBE_PROBE_ADDR /* only a --hp-probe build has it (tools/cycles_csr.py) */
    volatile uint32_t* probe = (volatile uint32_t*)CSR_ZMV_HP_PROBE_PROBE_ADDR;
    for (int i = 0; i < 8; i++) CPU(DIAG_PROBE_DDR)[i] = probe[i];
#endif
    return 4;
}

/* The word glass run --fw-opt writes (glass/src/map_cart.zig FW_OPT_*): the same word, the same bits. */
_Static_assert(DIAG_CTL_DDR + 8u == 0x06000000u - FW_OPT_FROM_TOP, "the switch word moved");
_Static_assert(FW_OPT_TAG >> 16 == DIAG_CFG_TAG && FW_OPT_PLANE_MAJOR == DIAG_OPT_PLANE_MAJOR &&
                   FW_OPT_KEEP_PFB == DIAG_OPT_KEEP_PFB && FW_OPT_W64 == 2u,
               "the switch bits differ");

uint32_t diag_opt;

void diag_apply_cfg(void) {
    zmv_flush_dcache();
    uint32_t w = CTL[2];
    if ((w >> 16) != DIAG_CFG_TAG) return;
    ZMV_REG(HP_CFG) = w & 3u;
    diag_opt = w & 0xffffu;
}

int diag_maybe(void) {
    diag_apply_cfg();
    if (CTL[0] != DIAG_MAGIC) return 0;
    uint32_t mode = CTL[1], result = 0;
    board_state(0x40u | (mode << 8));
    if (mode == 1) result = mode_1_stores();
    else if (mode == 2) result = mode_2_loads();
    else if (mode == 3) result = mode_3_dma();
    else if (mode == 4) result = mode_4_mix();
    board_beat(result);
    board_state(0x44u | (mode << 8));
#ifndef ZM_BOARD /* the sim: what the CPU reads back, md.l style, then the end */
    zmv_flush_dcache();
    static const uint32_t at[] = {DIAG_STORE_DDR, DIAG_STORE_DDR + 0x100, DIAG_STORE_DDR + 0x140,
                                  DIAG_VBASE_DDR + ZM_OFF_PFB, DIAG_VBASE_DDR + ZM_OFF_PFB + 0x640,
                                  DIAG_PIC_DDR, DIAG_PIC_DDR + 0x20, DIAG_PIC_DDR + 0xc80, DIAG_PROBE_DDR,
                                  DIAG_PROBE_DDR + 0x20, DIAG_PROBE_DDR + 0x30, DIAG_PROBE_DDR + 0x40};
    for (int a = 0; a < 12; a++)
        for (int i = 0; i < 8; i += 4)
            printf("ZM DIAG %08lx: %08lx %08lx %08lx %08lx\n", (unsigned long)(at[a] + 4 * i),
                   (unsigned long)CPU(at[a])[i], (unsigned long)CPU(at[a])[i + 1], (unsigned long)CPU(at[a])[i + 2],
                   (unsigned long)CPU(at[a])[i + 3]);
    printf("ZM DIAG result %08lx\n", (unsigned long)result);
    board_finish(0);
#endif
    for (;;) {
    }
}
