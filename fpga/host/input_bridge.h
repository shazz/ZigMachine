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

#endif
