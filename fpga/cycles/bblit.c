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
 *      response: when it falls the pixels are in DDR. With BLIT_ASYNC set (the cart's
 *      opt-in, bchisel.h) hwBlit returns at once and steps 3-4 wait for the next sync;
 *   4. invalidate the D-cache lines of the op's clipped box (the CPU's lines of those pixels
 *      are stale; bdinval.h, the whole cache when the box is bigger than it), and store
 *      CYCLES and STATUS where the machine leaves them, for the cart's loads.
 * The machine's code runs instead (its CPU stores are snooped like any other) before
 * vseq_init sets VBASE (the tap has no region yet), and for an op whose destination
 * starts below OFF_VRAM: D may legally write the region's registers and palettes, and
 * zm_blit's writes go to DDR behind both snoops (its own and the compositor's).
 *
 * The board image (ZM_BOARD) keeps no statistics: nothing on the board reads them (the sim's
 * "ZM BF"/"ZM BLIT" lines are their only readers), and they cost ~12 stores and 3 counter
 * reads a call, every store a blocking DDR write (~18 cycles, the ZIGGY bench's st.sw): about
 * half of what a small op costs through hwBlit. For the same reason CYCLES and STATUS are
 * stored only when they change (a run of equal ops leaves both as they were). */
#include "bblit.h"

#include <stdio.h>

#include "bchisel.h"
#include "vboard.h"
#include "zm_memmap.h"

struct w2c_machine;
void __real_w2c_machine_hwBlit(struct w2c_machine* m);
void __wrap_w2c_machine_hwBlit(struct w2c_machine* m);

bblit_stats bblit;

#ifndef ZM_BOARD
#define BBLIT_STATS 1
#endif

void bblit_frame_reset(void) {
    for (int i = 0; i < 5; i++) bblit.op_calls[i] = bblit.op_cycles[i] = bblit.op_units[i] = 0;
    bblit.n_trace = 0;
    bblit.t_last = board_cycles();
}

/* CHISEL's op: one into the planes, or a QUEUE (whose descriptors set their own D_BASE; CHISEL
 * refuses a queued op below OFF_VRAM as the machine does, so the block's D_BASE says nothing). */
static inline int chisel_takes(volatile uint8_t* r) {
    return r && (*(volatile uint32_t*)(r + ZM_BLIT_D_BASE) >= ZM_OFF_VRAM || r[ZM_BLIT_COMMAND] == ZM_BLIT_CMD_QUEUE);
}

#ifndef BBLIT_STATS
void __wrap_w2c_machine_hwBlit(struct w2c_machine* m) {
    volatile uint8_t* r = (volatile uint8_t*)(uintptr_t)ZMV_REG(VBASE);
#ifdef ZM_BLIT_HW
    if (chisel_takes(r)) {
        bchisel_run(r);
        return;
    }
    BCHISEL_SYNC(); /* the machine's own blitter writes with CPU stores: after the lazy op */
#endif
    __real_w2c_machine_hwBlit(m);
}
#else
void __wrap_w2c_machine_hwBlit(struct w2c_machine* m) {
    uint32_t t0 = board_cycles();
    volatile uint8_t* r = (volatile uint8_t*)(uintptr_t)ZMV_REG(VBASE);
    uint8_t cmd = r ? r[ZM_BLIT_COMMAND] : 0;
#ifdef ZM_BLIT_HW
    if (chisel_takes(r)) {
        bchisel_run(r);
        if (cmd) bblit.hw++;
    } else {
        BCHISEL_SYNC();
        __real_w2c_machine_hwBlit(m);
    }
#else
    __real_w2c_machine_hwBlit(m);
#endif
    uint32_t dt = board_cycles() - t0;
    bblit.calls++;
    bblit.cycles += dt;
    int k = cmd <= 4 ? cmd : 0;
    bblit.op_calls[k]++;
    bblit.op_cycles[k] += dt;
    uint32_t units = r && cmd ? *(volatile uint32_t*)(r + ZM_BLIT_CYCLES) : 0;
    bblit.op_units[k] += units;
    if (bblit.n_trace < BBLIT_TRACE) {
        bblit.trace[bblit.n_trace].cmd = cmd;
        bblit.trace[bblit.n_trace].gap = t0 - bblit.t_last;
        bblit.trace[bblit.n_trace].cycles = dt;
        bblit.trace[bblit.n_trace].units = units;
        bblit.n_trace++;
    }
    bblit.t_last = board_cycles();
}
#endif

/* Per frame (sim): "ZM BF f" then calls/cpu-cycles/units for BLIT FILL LINE TRIANGLE (bblit.h),
 * and "ZM WF f ibus_wait dbus_rd dbus_wr dbus_wait" (soc/zm_cycles.py) over the whole frame. */
#ifndef ZM_BOARD
void bblit_report_frame(long f, long trace, const uint32_t* c0, const uint32_t* c1) {
    printf("ZM BF %ld", f);
    for (int k = 1; k <= 4; k++)
        printf(" %lu %lu %lu", (unsigned long)bblit.op_calls[k], (unsigned long)bblit.op_cycles[k],
               (unsigned long)bblit.op_units[k]);
    if (f == trace)
        for (uint32_t i = 0; i < bblit.n_trace; i++)
            printf("\nZM BT %ld %lu %u %lu %lu %lu", f, (unsigned long)i, (unsigned)bblit.trace[i].cmd,
                   (unsigned long)bblit.trace[i].gap, (unsigned long)bblit.trace[i].cycles,
                   (unsigned long)bblit.trace[i].units);
    printf("\nZM WF %ld %lu %lu %lu %lu\n", f, (unsigned long)(c1[2] - c0[2]), (unsigned long)(c1[3] - c0[3]),
           (unsigned long)(c1[4] - c0[4]), (unsigned long)(c1[5] - c0[5]));
}
#endif
