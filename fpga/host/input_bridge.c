/* See input_bridge.h. The router names an export and an argument; this calls it on the cart
 * through host_input (generated per cart: NULL where the cart has no such export). */
#include "input_bridge.h"

#include <string.h>

#include "glass_input.h"

static void call(void* ctx, const char* name, int arg) {
    w2c_cart* c = ctx;
    const host_input_bridge* b = &host_input;
    uint32_t v = (uint32_t)arg;
    if (!strcmp(name, "input")) {
        if (b->input) b->input(c, v);
    } else if (!strcmp(name, "inputRelease")) {
        if (b->input_release) b->input_release(c, v);
    } else if (!strcmp(name, "key")) {
        if (b->key) b->key(c, v);
    } else if (!strcmp(name, "keyUp")) {
        if (b->key_up) b->key_up(c, v);
    } else if (!strcmp(name, "setShadeMode")) {
        if (b->shade) (void)b->shade(c, v);
    }
}

static void pointer(void* ctx, int x, int y, uint32_t buttons) {
    host_input.pointer((w2c_cart*)ctx, (uint32_t)x, (uint32_t)y, buttons);
}

void input_events(w2c_cart* cart, const uint32_t* events, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        /* ownsKeyboard() per event, as the browser asks it per keydown: a key may change it. */
        int owns = host_input.owns_keyboard ? (int)host_input.owns_keyboard(cart) : 0;
        glass_dispatch(events[i], owns, call, cart);
    }
}

void input_joy(w2c_cart* cart, uint32_t before, uint32_t now) { glass_joy(before, now, call, cart); }

int input_pointer(w2c_cart* cart, uint32_t ptr, uint32_t* seen) {
    return glass_pointer(ptr, seen, host_input.pointer ? pointer : NULL, cart);
}
