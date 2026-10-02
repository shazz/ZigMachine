/* The cart CPU's half of the glass's input path: key events and joypad bits
 * from the ARM (fpga/glass/src/map.zig: KEY_*, JOY_*) turned into the cart
 * export calls the browser makes (docs/sealed-loader.js keydown/keyup). The
 * rules need ownsKeyboard(), which only this side can ask the cart, which is
 * why the ARM sends neutral events and the routing lives here.
 *
 * Plain C, no LiteX: the board firmware feeds it the CSRs (glass_key_data,
 * glass_key_valid, glass_key_pop, glass_joy) and binds `call` to the cart's
 * exports; tests feed it directly. The map's constants come in as -D defines
 * (fpga/gen/glass_map.py), as for the RTL testbenches. */
#ifndef GLASS_INPUT_H
#define GLASS_INPUT_H

#include <stdint.h>

/* One cart call: export name ("input", "inputRelease", "key", "keyUp",
 * "setShadeMode") and its argument. A cart without that export ignores it. */
typedef void (*glass_call_fn)(void* ctx, const char* export_name, int arg);

/* What one event becomes; -1 = nothing of that kind. */
typedef struct {
    int input;   /* demo.input(dir) */
    int release; /* demo.inputRelease(dir) */
    int key;     /* demo.key(code) */
    int key_up;  /* demo.keyUp(code) */
    int shade;   /* demo.setShadeMode(n) */
} glass_route_t;

glass_route_t glass_route(uint32_t event, int owns_keyboard);

/* Route one event and make its calls, in the browser's order. */
void glass_dispatch(uint32_t event, int owns_keyboard, glass_call_fn call, void* ctx);

/* The joypad: input()/inputRelease() for every bit that changed. */
void glass_joy(uint32_t before, uint32_t now, glass_call_fn call, void* ctx);

#endif
