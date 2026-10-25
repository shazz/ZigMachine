/* The planner's view of a plane's copper list (HW 1.9.0, machine/copper.zig): included once, by
 * vdirty.c. A list sets its plane's palette (and HSCROLL, and the line's flicker) line by line, after
 * the palette the planner compares (that is the frame's start, where the WRITEBACK left the last
 * frame's end). So a plane whose list is word for word last frame's, with the same palette at the
 * start, paints every line as last frame did; one whose list changed, appeared or went, or that the
 * planner cannot read whole, has every line it covers composited again.
 *
 * A PALREF names palette words elsewhere in VRAM, which may change with the list unchanged: a list
 * with one is always treated as changed (tcb_colorshock's raster changes every frame anyway). */
#ifndef ZM_VDLIST_H
#define ZM_VDLIST_H

#include <stdint.h>
#include <string.h>

#include "zm_memmap.h"

#define VDL_MAX 4096u /* words a list may have and still be compared (zg.copper's: 2,801) */

static uint32_t vdl_copy[ZM_NB_PLANES][VDL_MAX];
static uint32_t vdl_len[ZM_NB_PLANES]; /* the copy's words; 0: no list last frame */
static uint8_t vdl_ok[ZM_NB_PLANES];   /* the copy holds a comparable list */

static uint32_t vdl_word(const vd_frame* fr, uint32_t off) {
    const uint8_t* b = fr->mem + ZM_HW_VIDEO_BASE + off;
    return (uint32_t)(b[0] | b[1] << 8 | b[2] << 16 | (uint32_t)b[3] << 24);
}

/* Plane p's list length in words, up to and including its end HEAD; 0 if it cannot be compared
 * (too long, leaving VRAM, a PALREF, or a record that would stop it on the machine). */
static uint32_t vdl_measure(const vd_frame* fr, uint32_t at) {
    const uint32_t end = ZM_OFF_VRAM + ZM_VRAM_BYTES;
    uint32_t words = 0;
    for (;;) {
        if (at + 4 > end || words + 1 > VDL_MAX) return 0;
        uint32_t head = vdl_word(fr, at), n = head & 0x3FFu;
        if (head >> 28 != 0xFu) return 0;
        words++;
        if (((head >> 19) & 0x1FFu) == 511u) return words;
        if (n > 253u || at + 4 + 4 * n > end || words + n > VDL_MAX) return 0;
        for (uint32_t i = 0; i < n; i++) {
            uint32_t op = vdl_word(fr, at + 4 + 4 * i) >> 28;
            if (op == 4u || op > 4u) return 0; /* PALREF, reserved */
        }
        words += n, at += 4 + 4 * n;
    }
}

/* Whether plane p's lines must be composited again because of its list (see above). */
static int vdl_moved(const vd_frame* fr, int p) {
#ifdef VD_BREAK_COPPER /* tests/test_vdirty.py's mutant: the lists ignored */
    (void)fr, (void)p;
    return 0;
#endif
    uint32_t v = (uint32_t)(fr->mem[ZM_HW_VIDEO_BASE + ZM_REG_FB_COPPER + 2u * (uint32_t)p] |
                            fr->mem[ZM_HW_VIDEO_BASE + ZM_REG_FB_COPPER + 2u * (uint32_t)p + 1] << 8);
    if (!v) {
        int had = vdl_len[p] != 0 || !vdl_ok[p];
        vdl_len[p] = 0, vdl_ok[p] = 1;
        return had;
    }
    uint32_t at = ZM_OFF_VRAM + 16u * v, n = vdl_measure(fr, at);
    if (!n) {
        vdl_ok[p] = 0;
        return 1;
    }
    const uint8_t* src = fr->mem + ZM_HW_VIDEO_BASE + at;
    int moved = !vdl_ok[p] || vdl_len[p] != n || memcmp(vdl_copy[p], src, 4 * n);
    if (moved) memcpy(vdl_copy[p], src, 4 * n);
    vdl_len[p] = n, vdl_ok[p] = 1;
    return moved;
}

/* Whether plane p's list opens with a PALREF record (its first line's body holds one): a list
 * whose lines name their palettes in VRAM, which vdl_moved always counts as changed. A cheap look
 * (the first record only): vd_plan then leaves the plane's rows uncompared (its covered lines are
 * new, as a handler plane's), so the plan costs nothing there and the borders still skip. A list
 * whose PALREFs come later has its rows compared, for nothing; never a wrong skip. */
static int vdl_palref_first(const vd_frame* fr, int p) {
#ifdef VD_BREAK_PALREF /* tests/test_vdirty.py's mutant: never seen */
    (void)fr, (void)p;
    return 0;
#endif
    uint32_t v = (uint32_t)(fr->mem[ZM_HW_VIDEO_BASE + ZM_REG_FB_COPPER + 2u * (uint32_t)p] |
                            fr->mem[ZM_HW_VIDEO_BASE + ZM_REG_FB_COPPER + 2u * (uint32_t)p + 1] << 8);
    uint32_t at = ZM_OFF_VRAM + 16u * v, end = ZM_OFF_VRAM + ZM_VRAM_BYTES;
    if (!v || at + 4 > end) return 0;
    uint32_t head = vdl_word(fr, at), n = head & 0x3FFu;
    if (head >> 28 != 0xFu || ((head >> 19) & 0x1FFu) == 511u || n > 253u || at + 4 + 4 * n > end) return 0;
    for (uint32_t i = 0; i < n; i++)
        if (vdl_word(fr, at + 4 + 4 * i) >> 28 == 4u) return 1;
    return 0;
}

#endif
