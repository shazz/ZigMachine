/* The glass's input, once a frame, before cart.frame() (docs/FPGA_GLASS.md "Input"): drain the
 * key FIFO (at most KEYS_A_FRAME, so a stuck FIFO cannot hold the frame), then the joypad's
 * changes, then the mouse, through host/input_bridge.c into the cart's exports. */
#include "binput.h"

#include "csr_addr.h"
#include "input_bridge.h"

#define KEYS_A_FRAME 32u
#define CSR(name) (*(volatile uint32_t*)CSR_GLASS_##name##_ADDR)

#ifdef ZM_SIM_KEYS
#include <stdio.h>
#include <stdlib.h>
/* The sim has no keyboard: ZM_SIM_KEYS="F:event,..." (cycles/board.mk, sim images only) is
 * host/main.c's ZM_GLASS_KEYS script, read as if the FIFO had held it, frames counted from 1. */
static uint32_t sim_keys(uint32_t* ev, uint32_t n) {
    static const char* at = ZM_SIM_KEYS;
    static long f;
    f++;
    while (*at && n < KEYS_A_FRAME) {
        char* end;
        long frame = strtol(at, &end, 10);
        if (*end != ':') {
            printf("ZM SIM KEYS bad at '%s'\n", at);
            at = "";
            break;
        }
        if (frame > f) break;
        uint32_t event = (uint32_t)strtoul(end + 1, &end, 16);
        at = end + (*end == ',');
        if (frame == f) ev[n++] = event;
    }
    return n;
}
#else
#define sim_keys(ev, n) (n)
#endif

void binput_frame(struct w2c_env* e) {
    static uint32_t joy, seen;
    uint32_t ev[KEYS_A_FRAME], n = 0;
    while (n < KEYS_A_FRAME && (CSR(KEY_VALID) & 1u)) {
        ev[n++] = CSR(KEY_DATA);
        CSR(KEY_POP) = 1u;
    }
    n = sim_keys(ev, n);
    input_events(&e->cart, ev, n);
    uint32_t now = CSR(JOY);
    input_joy(&e->cart, joy, now);
    joy = now;
    int seq = input_pointer(&e->cart, CSR(POINTER), &seen);
    if (seq >= 0) CSR(POINTER_ACK) = (uint32_t)seq;
}
