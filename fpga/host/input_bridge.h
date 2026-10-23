/* The glass's input to the cart (docs/FPGA_GLASS.md "Input"): its key events, joypad and mouse
 * turned into the cart's export calls by fpga/glass/firmware/glass_input.c, whose rules are
 * docs/sealed-loader.js's. The board firmware feeds it the glass CSRs (cycles/binput.c); the
 * native host feeds it a script (host/main.c ZM_GLASS_KEYS), which is how it is tested. A cart
 * without an export gets nothing for it (host_input's NULLs, tools/host_gen.py). */
#ifndef ZM_INPUT_BRIDGE_H
#define ZM_INPUT_BRIDGE_H

#include <stdint.h>

#include "host.h"

void input_events(w2c_cart* cart, const uint32_t* events, uint32_t n); /* KEY_* events, oldest first */
void input_joy(w2c_cart* cart, uint32_t before, uint32_t now);         /* JOY_* bits held */
int input_pointer(w2c_cart* cart, uint32_t ptr, uint32_t* seen);       /* PTR_*: the SEQ to ack, or -1 */

/* 1: the firmware draws GEM's arrow over this cart (cycles/bcursor.c). A cart that takes the mouse
 * (pointer) gets it, unless it draws its own pointer: its drawsOwnPointer export, which a cart has
 * only when it declares it (apps/zig/demo_main.zig), as the browser hides its cursor for it. */
int input_arrow(void);

/* The mouse as a script (host/main.c ZM_GLASS_POINTER, cycles/binput.c ZM_SIM_POINTER):
 * "F:word,..." with `word` (hex) what the ARM writes to REG_POINTER before frame F (x, y and the
 * held buttons, PTR_*). Each write bumps SEQ, as the PL does, so *ptr ends as the CSR the cart CPU
 * reads at frame f. The PL's button latch is not modelled: a script holds a press for a frame.
 * Returns 0, or -1 at a malformed entry (the rest of the script is dropped). */
int input_pointer_script(const char** at, long f, uint32_t* ptr);

#endif
