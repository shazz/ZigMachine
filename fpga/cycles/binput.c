/* The glass's input, once a frame, before cart.frame() (docs/FPGA_GLASS.md "Input"): drain the
 * key FIFO (at most KEYS_A_FRAME, so a stuck FIFO cannot hold the frame), then the joypad's
 * changes, then the mouse, through host/input_bridge.c into the cart's exports. */
#include "binput.h"

#include "csr_addr.h"
#include "input_bridge.h"

#define KEYS_A_FRAME 32u
#define CSR(name) (*(volatile uint32_t*)CSR_GLASS_##name##_ADDR)

#if defined(ZM_SIM_KEYS) || defined(ZM_SIM_POINTER)
#include <stdio.h>
#include <stdlib.h>
#endif

#ifdef ZM_SIM_KEYS
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

#ifdef ZM_SIM_POINTER
/* ZM_SIM_POINTER="F:word,..." (sim images only): host/main.c's ZM_GLASS_POINTER, the mouse the
 * ARM would have written, in place of the CSR. */
static uint32_t sim_pointer(uint32_t csr) {
    static const char* at = ZM_SIM_POINTER;
    static uint32_t ptr;
    static long f;
    (void)csr;
    if (input_pointer_script(&at, ++f, &ptr)) printf("ZM SIM POINTER bad before frame %ld\n", f);
    return ptr;
}
#else
#define sim_pointer(csr) (csr)
#endif

void binput_frame(struct w2c_env* e) {
    static uint32_t joy, seen;
    uint32_t ev[KEYS_A_FRAME], n = 0;
    while (n < KEYS_A_FRAME && (CSR(KEY_VALID) & 1u)) {
        ev[n++] = CSR(KEY_DATA);
        CSR(KEY_POP) = 1u;
    }
    n = sim_keys(ev, n);
    input_events(HOST_CART(e), ev, n);
    uint32_t now = CSR(JOY);
    input_joy(HOST_CART(e), joy, now);
    joy = now;
    int seq = input_pointer(HOST_CART(e), sim_pointer(CSR(POINTER)), &seen);
    if (seq >= 0) CSR(POINTER_ACK) = (uint32_t)seq;
}
