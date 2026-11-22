/* See input_bridge.h. The router names an export and an argument; this calls it on the cart
 * through host_input (generated per cart: NULL where the cart has no such export). */
#include "input_bridge.h"

#include <stdlib.h>
#include <string.h>

#include "glass_input.h"
#include "glass_map.h" /* PTR_*: the pointer script builds the CSR word */

/* Player 2 (R83): the cart's optional input2/inputRelease2 exports, found by name in its export
 * table (host_exports) so host_input_bridge, a layout the board's system image and its carts
 * share (sys_abi.txt), does not change. A cart without both gets player 2 merged into input(). */
static const host_export* p2_table; /* the export table looked at last: a lean cart's own, per cart */
static const host_export *p2_in, *p2_out;

static const host_export* export_named(const char* name) {
    for (const host_export* x = host_exports; x->name; x++)
        if (!strcmp(x->name, name)) return x;
    return NULL;
}

static int has_p2(void) {
    if (p2_table != host_exports) {
        p2_table = host_exports;
        p2_in = export_named("input2");
        p2_out = export_named("inputRelease2");
    }
    return p2_in && p2_out;
}

static uint32_t held[2]; /* the JOY_* bits each player's pad holds, as last delivered */

/* `ctx` is the host: the export table's functions take it, not the cart. */
static void call_p2(void* ctx, const char* name, int arg) {
    const double a[1] = {(double)arg};
    const host_export* x = !strcmp(name, "input") ? p2_in : p2_out;
    x->fn(ctx, a);
}

static void call(void* ctx, const char* name, int arg);

/* One player's pad now holds `now`: its edges are input()/inputRelease() for player 1, input2()/
 * inputRelease2() for player 2, or, for a cart without those, the edges of both pads' union. */
static void pad_set(struct w2c_env* e, int player, uint32_t now) {
    const uint32_t old[2] = {held[0], held[1]};
    held[player] = now;
    if (has_p2()) glass_joy(old[player], now, player ? call_p2 : call, e);
    else glass_joy(old[0] | old[1], held[0] | held[1], call, e);
}

static void call(void* ctx, const char* name, int arg) {
    struct w2c_env* e = ctx;
    w2c_cart* c = HOST_CART(e);
    const host_input_bridge* b = &host_input;
    if (!strcmp(name, "pad2")) return pad_set(e, 1, (uint32_t)arg);
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

void input_events(struct w2c_env* e, const uint32_t* events, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        /* ownsKeyboard() per event, as the browser asks it per keydown: a key may change it. */
        int owns = host_input.owns_keyboard ? (int)host_input.owns_keyboard(HOST_CART(e)) : 0;
        glass_dispatch(events[i], owns, call, e);
    }
}

void input_joy(struct w2c_env* e, uint32_t before, uint32_t now) {
    held[0] = before;
    pad_set(e, 0, now);
}

int input_pointer(w2c_cart* cart, uint32_t ptr, uint32_t* seen) {
    return glass_pointer(ptr, seen, host_input.pointer ? pointer : NULL, cart);
}

int input_arrow(void) {
    static const host_export* seen; /* the export table looked at last: a lean cart's own, per cart */
    static int own;
    if (!host_input.pointer) return 0;
    if (seen != host_exports) {
        seen = host_exports;
        own = 0;
        for (const host_export* x = seen; x->name; x++) own |= !strcmp(x->name, "drawsOwnPointer");
    }
    return !own;
}

int input_pointer_script(const char** at, long f, uint32_t* ptr) {
    while (**at) {
        char* end;
        long frame = strtol(*at, &end, 10);
        if (end == *at || *end != ':') return *at = "", -1;
        if (frame > f) break;
        const char* word = end + 1;
        uint32_t write = (uint32_t)strtoul(word, &end, 16);
        if (end == word || (*end && *end != ',')) return *at = "", -1;
        *at = end + (*end == ',');
        if (frame < f) continue; /* a past frame: the script was not played from frame 1 */
        uint32_t seq = ((*ptr >> PTR_SEQ_SHIFT) + 1u) & PTR_SEQ_MASK;
        *ptr = (write & ~(PTR_SEQ_MASK << PTR_SEQ_SHIFT)) | (seq << PTR_SEQ_SHIFT);
    }
    return 0;
}
