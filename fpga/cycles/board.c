/* picolibc's stdio on the sim UART, and the way out of the simulation. */
#include "board.h"

#include <stdio.h>

static int uart_putc(char c, FILE* f) {
    (void)f;
    while (*(volatile uint32_t*)CSR_UART_TXFULL_ADDR) {
    }
    *(volatile uint32_t*)CSR_UART_RXTX_ADDR = (uint8_t)c;
    return (uint8_t)c;
}

/* stdout and stderr share the one UART; the runner tells them apart by prefix. */
static FILE g_uart = FDEV_SETUP_STREAM(uart_putc, NULL, NULL, _FDEV_SETUP_WRITE);
FILE* const stdin = &g_uart;
FILE* const stdout = &g_uart;
FILE* const stderr = &g_uart;

void board_finish(int code) {
    printf("ZM END %d\n", code);
    while (!*(volatile uint32_t*)CSR_UART_TXEMPTY_ADDR) {
    }
    *(volatile uint32_t*)CSR_SIM_FINISH_FINISH_ADDR = 1;
    for (;;) {
    }
}

/* picolibc's exit() lands here (main returning, abort, wasm2c's abort()). */
void _exit(int code) { board_finish(code); }
