/* The glass's input, once a frame, before cart.frame() (docs/FPGA_GLASS.md "Input"): drain the
 * key FIFO (at most KEYS_A_FRAME, so a stuck FIFO cannot hold the frame), then the joypad's
 * changes, then the mouse, through host/input_bridge.c into the cart's exports. */
#include "binput.h"

#include "csr_addr.h"
#include "input_bridge.h"

#define KEYS_A_FRAME 32u
#define CSR(name) (*(volatile uint32_t*)CSR_GLASS_##name##_ADDR)

void binput_frame(struct w2c_env* e) {
    static uint32_t joy, seen;
    uint32_t ev[KEYS_A_FRAME], n = 0;
    while (n < KEYS_A_FRAME && (CSR(KEY_VALID) & 1u)) {
        ev[n++] = CSR(KEY_DATA);
        CSR(KEY_POP) = 1u;
    }
    input_events(&e->cart, ev, n);
    uint32_t now = CSR(JOY);
    input_joy(&e->cart, joy, now);
    joy = now;
    int seq = input_pointer(&e->cart, CSR(POINTER), &seen);
    if (seq >= 0) CSR(POINTER_ACK) = (uint32_t)seq;
}
