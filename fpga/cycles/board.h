/* The cycles SoC as the firmware sees it (soc/cycles_sim.py): the ZMCycles
 * counters, the sim UART and the sim's finish register. Addresses come from
 * the SoC's csr.json through tools/cycles_csr.py (csr_addr.h), never retyped. */
#ifndef ZM_BOARD_H
#define ZM_BOARD_H

#include <stdint.h>

#include "csr_addr.h"

/* soc/zm_cycles.py COUNTERS, in that order: cycles, ibus_ack, ibus_wait,
 * dbus_rd, dbus_wr, dbus_wait. All free-running mod 2^32. */
#define ZM_NCOUNT 6

static inline uint32_t board_cycles(void) {
    return *(volatile uint32_t*)CSR_ZM_CYCLES_CYCLES_ADDR;
}

/* One uncached load per counter, in counter order. */
static inline void board_counters(uint32_t out[ZM_NCOUNT]) {
    volatile uint32_t* r = (volatile uint32_t*)CSR_ZM_CYCLES_CYCLES_ADDR;
    for (int i = 0; i < ZM_NCOUNT; i++) out[i] = r[i];
}

/* Ends the simulation ($finish). The runner reads the exit code from the
 * "ZM END" line, because Verilator's own exit status does not carry it. */
__attribute__((noreturn)) void board_finish(int code);

#endif
