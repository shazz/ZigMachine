/* cycles/bchisel.c on the host, over a model of CHISEL and its tap (soc/zm_blit_soc.py,
 * rtl/blitter/zm_blit_regs.v, zm_blit_q.v): every cart store reaches the tap bank, also while
 * BUSY (never dropped); GO copies that bank for the engine and records its word; BUSY stays up
 * for OP_POLLS reads of STATUS; a GO while BUSY is a firmware bug the model counts.
 * tests/test_chisel_async.py builds it (and its mutants) and reads the verdicts: "OK <case>"
 * lines, "FAIL <case>: why" and a non-zero exit otherwise. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <stdint.h>

#define ZM_BLIT_HW 1
#define OP_POLLS 40
#define WORDS 24

static uint32_t engine[WORDS], at_go[WORDS]; /* zm_blit's tap bank; what the last GO copied */
static uint32_t go_word;
static int polls_left, gos, go_while_busy;
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
static void win_go(uint32_t word) {
    go_while_busy += busy();
    memcpy(at_go, engine, sizeof at_go);
    go_word = word, polls_left = OP_POLLS, gos++;
}
#define BCHISEL_RD(i) win_rd(i)
#define BCHISEL_GO(word) win_go(word)
#define BDI_INVAL_LINE(a) (n_lines < 4096 ? (void)(lines[n_lines++] = (a)) : (void)0)

#include "bchisel.c"

static uint8_t* region;

static void cart_w32(uint32_t off, uint32_t v) {
    *(uint32_t*)(region + off) = v;
    if (off >= ZM_OFF_BLIT && off < ZM_OFF_BLIT + 4 * WORDS) engine[(off - ZM_OFF_BLIT) / 4] = v;
}

/* A FILL of w x h at (x, y) of a 320-wide plane at VRAM: every register through the cart's stores. */
static void cart_fill(int x, int y, int w, int h) {
    cart_w32(ZM_BLIT_D_BASE, ZM_OFF_VRAM);
    cart_w32(ZM_BLIT_D_STRIDE, 320);
    cart_w32(ZM_BLIT_X0, (uint32_t)x | (uint32_t)y << 16);
    cart_w32(ZM_BLIT_W, (uint32_t)w | (uint32_t)h << 16);
    region[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_FILL;
}

static void cart_queue(uint32_t start, uint32_t count) {
    cart_w32(ZM_BLIT_Q_START, start | count << 16);
    region[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_QUEUE;
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

static void nop(void) {
    region[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_NOP, n_lines = 0, swept = 0;
    bchisel_run(region); /* zg.chisel_async.sync(), the queue's flush: a NOP hwBlit */
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
    cart_fill(100, 50, 16, 2); /* the next op's registers, stored while CHISEL is busy: kept by the tap */
    bchisel_run(region);
    check(lines_are_box(8, 4, 40, 3) && !go_while_busy, "lazy_invalidates_the_first_ops_box",
          "the lazy op's lines were taken from the registers at the sync, not at its GO");
    check(at_go[(ZM_BLIT_X0 - ZM_OFF_BLIT) / 4] == (100u | 50u << 16) && go_word == ZM_BLIT_CMD_FILL,
          "next_op_runs_with_the_stores_made_while_busy", "the second op ran with the first op's registers");
    nop();
    check(!busy() && !bchisel_pending && lines_are_box(100, 50, 16, 2), "nop_syncs", "a NOP did not wait for the lazy op");
    region[ZM_BLIT_ASYNC] = 0;
}

static void queue_mode(void) {
    region[ZM_BLIT_ASYNC] = 0, gos = 0, n_lines = 0, swept = 0;
    cart_queue(100, 37);
    bchisel_run(region);
    check(gos == 1 && go_word == (ZM_BLIT_CMD_QUEUE | 100u << 8 | 37u << 17), "queue_kick_carries_the_range",
          "the GO word is not COMMAND | start << 8 | count << 17");
    check(busy() && bchisel_pending && n_lines == 0 && !swept, "queue_is_lazy", "a QUEUE waited without BLIT_ASYNC");
    cart_fill(0, 0, 8, 8);
    bchisel_run(region);
    check(swept && !go_while_busy, "queue_sync_sweeps_the_dcache", "the next op did not wait or the D$ kept the list's lines");
    nop();
    uint32_t before = gos;
    *(uint32_t*)(region + ZM_BLIT_CYCLES) = 77;
    cart_queue(0, 0);
    bchisel_run(region);
    int empty = gos == before && *(uint32_t*)(region + ZM_BLIT_CYCLES) == 0 && !bchisel_pending;
    cart_queue(ZM_BLIT_QUEUE_WORDS - 4, 5);
    bchisel_run(region);
    check(empty && gos == before && !bchisel_pending, "queue_refused_like_the_machine",
          "an empty list or one past the ring's end reached CHISEL");
    cart_queue(ZM_BLIT_QUEUE_WORDS - 4, 4);
    bchisel_run(region);
    nop();
    check(gos == before + 1, "queue_up_to_the_rings_end_runs", "a list ending on the ring's last word was refused");
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
    queue_mode();
    hooks();
    return failed;
}
