/* cycles/bchisel.c on the host, over a model of CHISEL and its tap (soc/zm_blit_soc.py,
 * rtl/blitter/zm_blit_regs.v): GO snapshots the block the engine will read, BUSY stays up for
 * OP_POLLS reads of STATUS, and a store reaching the tap while BUSY is DROPPED, as in the RTL.
 * The cart's register stores go through cart_w32 (memory, then the tap); the firmware's replay
 * through BCHISEL_PUT. tests/test_chisel_async.py builds it (and its mutants) and reads the
 * verdicts: "OK <case>" lines, "FAIL <case>: why" and a non-zero exit otherwise. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <stdint.h>

#define ZM_BLIT_HW 1
#define OP_POLLS 40
#define WORDS 24

static uint32_t engine[WORDS], at_go[WORDS]; /* zm_blit's copy of the block; what the last GO read */
static int polls_left, gos;
static uintptr_t lines[4096];
static int n_lines;
int swept; /* stubs/dflush.h: the whole-cache invalidate */

static int busy(void) { return polls_left > 0; }
static uint32_t win_rd(int i) {
    if (i != 0) return 0x1234u; /* CYCLES */
    if (!busy()) return 0;
    polls_left--;
    return 1u << 31;
}
static void win_go(uint8_t cmd) {
    (void)cmd;
    memcpy(at_go, engine, sizeof at_go);
    polls_left = OP_POLLS, gos++;
}
static void tap(volatile uint32_t* w, uint32_t i) { /* the tap never takes COMMAND (byte 0 of word 0) */
    if (busy()) return;
    engine[i] = i == 0 ? (engine[0] & 0xFFu) | (w[0] & ~0xFFu) : w[i];
}
#define BCHISEL_RD(i) win_rd(i)
#define BCHISEL_GO(cmd) win_go(cmd)
#define BCHISEL_PUT(w, i) tap(w, i)
#define BDI_INVAL_LINE(a) (n_lines < 4096 ? (void)(lines[n_lines++] = (a)) : (void)0)

#include "bchisel.c"

static uint8_t* region;

static void cart_w32(uint32_t off, uint32_t v) {
    *(uint32_t*)(region + off) = v;
    tap((volatile uint32_t*)(region + ZM_OFF_BLIT), (off - ZM_OFF_BLIT) / 4);
}

/* A FILL of w x h at (x, y) of a 320-wide plane at VRAM: every register through the cart's stores. */
static void cart_fill(int x, int y, int w, int h) {
    cart_w32(ZM_BLIT_D_BASE, ZM_OFF_VRAM);
    cart_w32(ZM_BLIT_D_STRIDE, 320);
    cart_w32(ZM_BLIT_X0, (uint32_t)x | (uint32_t)y << 16);
    cart_w32(ZM_BLIT_W, (uint32_t)w | (uint32_t)h << 16);
    region[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_FILL;
}

static int failed;
static void check(int ok, const char* name, const char* why) {
    printf(ok ? "OK %s\n" : "FAIL %s: %s\n", name, why);
    failed |= !ok;
}

/* Exactly the lines of [x, x+w) x [y, y+h) on the 320-wide plane, row by row, and no sweep. */
static int lines_are_box(int x, int y, int w, int h) {
    int k = 0;
    for (int j = 0; j < h; j++) {
        uintptr_t a = (uintptr_t)region + ZM_OFF_VRAM + (uintptr_t)(y + j) * 320u + (uintptr_t)x;
        for (uintptr_t l = a & ~(uintptr_t)31; l < a + (uintptr_t)w; l += 32, k++)
            if (k >= n_lines || lines[k] != l) return 0;
    }
    return k == n_lines && !swept;
}

static void sync_mode(void) {
    region[ZM_BLIT_ASYNC] = 0, n_lines = 0;
    cart_fill(8, 4, 40, 3);
    bchisel_run(region);
    check(!busy() && !bchisel_pending, "sync_waits", "a synchronous hwBlit returned with CHISEL busy");
    check(lines_are_box(8, 4, 40, 3), "sync_invalidates_its_box", "the op's lines were not the ones dropped");
}

static void lazy_mode(void) {
    region[ZM_BLIT_ASYNC] = 1, n_lines = 0;
    cart_fill(8, 4, 40, 3);
    bchisel_run(region);
    check(busy() && bchisel_pending && n_lines == 0, "lazy_returns_at_once", "the lazy kick waited or invalidated");
    cart_fill(100, 50, 16, 2); /* the next op's registers, stored while CHISEL is busy: dropped */
    bchisel_run(region);
    check(lines_are_box(8, 4, 40, 3), "lazy_invalidates_the_first_ops_box",
          "the lazy op's lines were taken from the registers at the sync, not at its GO");
    check(at_go[(ZM_BLIT_X0 - ZM_OFF_BLIT) / 4] == (100u | 50u << 16) && at_go[(ZM_BLIT_W - ZM_OFF_BLIT) / 4] == (16u | 2u << 16),
          "replay_restores_dropped_registers", "the second op ran with the first op's registers");
    region[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_NOP, n_lines = 0;
    bchisel_run(region); /* zg.chisel_async.sync(): a NOP hwBlit */
    check(!busy() && !bchisel_pending && lines_are_box(100, 50, 16, 2), "nop_syncs", "a NOP did not wait for the lazy op");
    region[ZM_BLIT_ASYNC] = 0;
}

static void hooks(void) {
    region[ZM_BLIT_ASYNC] = 1;
    cart_fill(0, 0, 8, 8);
    bchisel_run(region);
    HOST_CHISEL_SYNC(); /* what the generated env puts before every machine and ROM entry */
    check(!busy() && !bchisel_pending, "env_hook_syncs", "HOST_CHISEL_SYNC left the lazy op running");
    region[ZM_BLIT_ASYNC] = 0;
}

int main(void) {
    region = aligned_alloc(4096, ZM_REGION_BYTES); /* the region's lines line up as on the board */
    if (region) memset(region, 0, ZM_REGION_BYTES);
    if (!region) return 2;
    sync_mode();
    lazy_mode();
    hooks();
    return failed;
}
