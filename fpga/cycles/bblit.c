/* hwBlit() on the board: rtl/blitter's zm_blit (soc/zm_blit_soc.py) in place of the
 * machine's software blitter. The board link wraps the machine's export
 * (-Wl,--wrap=w2c_machine_hwBlit, cycles/board.mk), so env.hwBlit from the cart and
 * the ROM lands here; ZM_BLIT_HW picks the RTL, else the machine's own code runs
 * (timed either way, for the HW vs SW figures).
 *
 * The machine's contract (machine/blitter.zig execute(), synchronous): COMMAND is
 * read when hwBlit() is called; NOP returns at once; anything else leaves the
 * pixels in memory, CYCLES = the op's cost and STATUS = 0. Here:
 *   1. the registers are already in zm_blit: the tap took every store to the
 *      block (the COMMAND byte excepted) as it left the CPU;
 *   2. GO = the command byte stored to BLIT_WINDOW word 0, through the same tap, so
 *      after every register store before it;
 *   3. spin on STATUS.BUSY, which covers the tap, the op and every write's B
 *      response: when it falls the pixels are in DDR;
 *   4. invalidate the D-cache (the CPU's lines of those pixels are stale), and
 *      store CYCLES and STATUS where the machine leaves them, for the cart's loads.
 * The machine's code runs instead (its CPU stores are snooped like any other) before
 * vseq_init sets VBASE (the tap has no region yet), and for an op whose destination
 * starts below OFF_VRAM: D may legally write the region's registers and palettes, and
 * zm_blit's writes go to DDR behind both snoops (its own and the compositor's). */
#include "bblit.h"

#include "vboard.h"
#include "zm_memmap.h"

struct w2c_machine;
void __real_w2c_machine_hwBlit(struct w2c_machine* m);
void __wrap_w2c_machine_hwBlit(struct w2c_machine* m);

bblit_stats bblit;

#ifdef ZM_BLIT_HW
#define BLIT_BUSY (1u << 31)
#define BLIT_TIMEOUT 100000000u /* cycles: 1 s at 100 MHz; the biggest op is ~27 Mc a frame */

static void blit_rtl(volatile uint8_t* r) {
    uint8_t cmd = r[ZM_BLIT_COMMAND];
    if (cmd == 0) return; /* NOP: the machine leaves STATUS and CYCLES alone */
    volatile uint32_t* w = (volatile uint32_t*)ZMB_WINDOW_ADDR;
    *(volatile uint8_t*)w = cmd;
    /* An op that never ends (a lost AXI response on HP2, a stuck sequencer) traps the cart
     * instead of hanging it: CART_STATE = 3 | 0xB1 << 24 | STATUS[15:0] << 8, read by the ARM
     * (zm_blit_core dbg: {op[2:0], st[2:0], px_idle, rd v/r, wr v/r, wr_pending, seq px_valid[3:0]}). */
    uint32_t t = board_cycles();
    while (w[0] & BLIT_BUSY) {
        if (board_cycles() - t > BLIT_TIMEOUT) board_finish((int)(0xB10000u | (w[0] & 0xFFFFu)));
    }
    zmv_flush_dcache();
    *(volatile uint32_t*)(r + ZM_BLIT_CYCLES) = w[ZM_BLIT_CYCLES / 4 - ZM_OFF_BLIT / 4];
    r[ZM_BLIT_STATUS] = 0;
    bblit.hw++;
}
#endif

void __wrap_w2c_machine_hwBlit(struct w2c_machine* m) {
    uint32_t t0 = board_cycles();
#ifdef ZM_BLIT_HW
    volatile uint8_t* r = (volatile uint8_t*)(uintptr_t)ZMV_REG(VBASE);
    if (r && *(volatile uint32_t*)(r + ZM_BLIT_D_BASE) >= ZM_OFF_VRAM) blit_rtl(r);
    else __real_w2c_machine_hwBlit(m);
#else
    __real_w2c_machine_hwBlit(m);
#endif
    bblit.calls++;
    bblit.cycles += board_cycles() - t0;
}
