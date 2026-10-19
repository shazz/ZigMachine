/* hwBlit's own cost on the board's cart core (tests/test_blit_path.py, tests/tb/dcache_tb.cpp):
 * cycles/bblit.c as the board image builds it (ZM_BOARD, ZM_BLIT_HW), its CSRs and CHISEL's
 * window answered by the harness (csr_addr.h here), every store held as long as a blocking DDR
 * write. CHISEL is never busy here, so what is timed is everything hwBlit adds to an op: the
 * wrapper, GO, one poll, the D$ range invalidate, CYCLES and STATUS. Against it, the floor: GO
 * and one poll, what the ZIGGY bench's chisel_go_fill + chisel_wait pay (ch.raw.*).
 * Checks the contract too: CYCLES and STATUS as the machine leaves them, the machine's own code
 * (__real) for a region below OFF_VRAM and before VBASE is set.
 * REPORT tag * 1000000 + value: 1 cycles a call, 2 bus writes a call (hwBlit, 8x8 FILL, warm),
 * 3 / 4 the same for GO + poll. Exit 0, or the first check that failed. */
#include <stdint.h>

#include "bblit.h"
#include "zm_memmap.h"

#define DEV ((volatile uint32_t*)0xf0000000u)
#define REGION ((volatile uint8_t*)0x40100000u)
#define WINDOW ((volatile uint32_t*)0x91000000u)
#define CALLS 64

struct w2c_machine;
void __wrap_w2c_machine_hwBlit(struct w2c_machine* m);

static volatile uint32_t real_calls;
void __real_w2c_machine_hwBlit(struct w2c_machine* m) {
    (void)m;
    real_calls++;
}
void board_finish(int code) {
    DEV[0] = (uint32_t)code;
    for (;;) {
    }
}

static void report(uint32_t tag, uint32_t v) { DEV[2] = tag * 1000000u + v; }
static uint32_t u32(uint32_t off) { return *(volatile uint32_t*)(REGION + off); }
static void set32(uint32_t off, uint32_t v) { *(volatile uint32_t*)(REGION + off) = v; }
static void set16(uint32_t off, uint16_t v) { *(volatile uint16_t*)(REGION + off) = v; }

static void fill8x8(void) { /* an 8x8 FILL at the top of VRAM, as the bench's ch.fill8 */
    REGION[ZM_BLIT_COMMAND] = ZM_BLIT_CMD_FILL;
    REGION[ZM_BLIT_CON] = 0;
    set32(ZM_BLIT_D_BASE, ZM_OFF_VRAM);
    set16(ZM_BLIT_D_STRIDE, 320);
    set32(ZM_BLIT_X0, 0);
    set16(ZM_BLIT_W, 8);
    set16(ZM_BLIT_H, 8);
}

static void time_calls(uint32_t tag) {
    uint32_t t0 = DEV[1], w0 = DEV[8];
    for (int i = 0; i < CALLS; i++) __wrap_w2c_machine_hwBlit(0);
    uint32_t t1 = DEV[1], w1 = DEV[8];
    report(tag, (t1 - t0) / CALLS);
    report(tag + 1, (w1 - w0) / CALLS);
}

static void time_raw(uint32_t tag) {
    uint32_t t0 = DEV[1], w0 = DEV[8];
    for (int i = 0; i < CALLS; i++) {
        *(volatile uint8_t*)WINDOW = ZM_BLIT_CMD_FILL;
        while (WINDOW[0] & (1u << 31)) {
        }
    }
    uint32_t t1 = DEV[1], w1 = DEV[8];
    report(tag, (t1 - t0) / CALLS);
    report(tag + 1, (w1 - w0) / CALLS);
}

int main(void) {
    fill8x8();
    __wrap_w2c_machine_hwBlit(0); /* VBASE not set yet: the machine's code */
    if (real_calls != 1) return 1;
    DEV[6] = (uint32_t)(uintptr_t)REGION; /* VBASE */
    DEV[7] = 64;                          /* the op's CYCLES, as CHISEL's window answers it */
    set32(ZM_BLIT_CYCLES, 0xDEAD);
    REGION[ZM_BLIT_STATUS] = 0x80;
    __wrap_w2c_machine_hwBlit(0);
    if (real_calls != 1) return 2;
    if (u32(ZM_BLIT_CYCLES) != 64 || REGION[ZM_BLIT_STATUS] != 0) return 3;
    time_calls(1);
    if (u32(ZM_BLIT_CYCLES) != 64 || REGION[ZM_BLIT_STATUS] != 0 || real_calls != 1) return 4;
    time_raw(3);
    set32(ZM_BLIT_D_BASE, ZM_OFF_VRAM - 1); /* D may write the registers: the machine's code */
    __wrap_w2c_machine_hwBlit(0);
    if (real_calls != 2) return 5;
    return 0;
}
