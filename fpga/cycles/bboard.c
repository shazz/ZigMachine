/* board.c for the board's SoC (soc/zm_board_mem.py: the z7 bitstream, and
 * soc/hp_sim.py that simulates it). The firmware's state goes to the glass's
 * CART_STATE / CART_BEAT, which the ARM reads over GP0 (0x43c00010 / 14), so a
 * run on the board says how it is doing without a console.
 *
 *   ZM_BOARD  the bitstream: the JTAG UART has no reader, so nothing is printed
 *             (a blocking putc would hang the cart on its first line), and the
 *             end is a spin with CART_STATE = TRAPPED | code << 8.
 *   else      the sim: picolibc's stdio on the sim UART, and $finish. */
#include <stdio.h>

#include "board.h"
#include "bboard.h"
#include "bmicros.h"

static int uart_putc(char c, FILE* f) {
    (void)f;
#ifndef ZM_BOARD
    while (*(volatile uint32_t*)CSR_UART_TXFULL_ADDR) {
    }
    *(volatile uint32_t*)CSR_UART_RXTX_ADDR = (uint8_t)c;
#endif
    return (uint8_t)c;
}

static FILE g_uart = FDEV_SETUP_STREAM(uart_putc, NULL, NULL, _FDEV_SETUP_WRITE);
FILE* const stdin = &g_uart;
FILE* const stdout = &g_uart;
FILE* const stderr = &g_uart;

void board_state(uint32_t state) { *(volatile uint32_t*)CSR_GLASS_CART_STATE_ADDR = state; }

void board_beat(uint32_t frames) { *(volatile uint32_t*)CSR_GLASS_CART_BEAT_ADDR = frames; }

#ifndef ZM_SYS_MHZ
#define ZM_SYS_MHZ 100u /* every board bitstream runs sys at 100 MHz (soc/zm_z7.py --sys-mhz) */
#endif

/* The cycle counter is 32 bits and wraps every 43 s at 100 MHz: its deltas go into 64 bits,
 * so the microseconds wrap like the browser's (u32, ~71 min), given calls under 43 s apart. */
uint32_t board_micros(void) {
    static uint32_t last;
    static uint64_t total;
    uint32_t now = board_cycles();
    total += (uint32_t)(now - last);
    last = now;
    return (uint32_t)(total / ZM_SYS_MHZ);
}

void board_finish(int code) {
    printf("ZM END %d\n", code);
    board_state(code ? ZM_CART_TRAPPED | ((uint32_t)code << ZM_CART_ARG_SHIFT) : ZM_CART_RESET);
#ifndef ZM_BOARD
    while (!*(volatile uint32_t*)CSR_UART_TXEMPTY_ADDR) {
    }
    *(volatile uint32_t*)CSR_SIM_FINISH_FINISH_ADDR = 1;
#endif
    for (;;) {
    }
}

/* picolibc's exit() lands here (main returning, abort, wasm2c's abort()). */
void _exit(int code) { board_finish(code); }
