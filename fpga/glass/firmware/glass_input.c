/* See glass_input.h. Each rule cites the line of docs/sealed-loader.js it
 * reproduces; that file stays the reference. */
#include "glass_input.h"

#define CODE(ev) ((ev) & KEY_CODE_MASK)

static int is_arrow(uint32_t c) { return c >= KEY_ARROW_UP && c <= KEY_ARROW_RIGHT; }
static int is_mod(uint32_t c) { return c >= KEY_CTRL_LEFT && c <= KEY_SHIFT_RIGHT; }

/* directionOf(): arrows always; WASD, Enter and Space only when the cart does
 * not own the keyboard. The browser compares evt.key, so 'W' is not 'w'. */
static int direction(uint32_t c, int owns) {
    if (c == KEY_ARROW_UP || (!owns && c == 'w')) return 0;
    if (c == KEY_ARROW_DOWN || (!owns && c == 's')) return 1;
    if (c == KEY_ARROW_LEFT || (!owns && c == 'a')) return 2;
    if (c == KEY_ARROW_RIGHT || (!owns && c == 'd')) return 3;
    if (!owns && (c == KEY_ENTER || c == ' ')) return 5;
    return -1;
}

glass_route_t glass_route(uint32_t ev, int owns) {
    glass_route_t r = {-1, -1, -1, -1, -1};
    uint32_t c = CODE(ev);
    if (!(ev & KEY_DOWN)) {
        r.release = direction(c, owns);
        r.key_up = is_arrow(c) ? -1 : (int)c; /* keyUpCode(): no code for an arrow */
        return r;
    }
    /* "+"/"-" change channel in the browser; on the board the OSD does that. */
    if (!owns && (c == '+' || c == '-')) return r;
    r.input = direction(c, owns);
    if (!owns && c >= '1' && c <= '7') r.shade = (int)(c - '1');
    /* demo.key(): every code but the arrows; a modifier only on its first press. */
    if (!is_arrow(c) && !(is_mod(c) && (ev & KEY_REPEAT))) r.key = (int)c;
    return r;
}

void glass_dispatch(uint32_t ev, int owns, glass_call_fn call, void* ctx) {
    glass_route_t r = glass_route(ev, owns);
    if (r.input >= 0) call(ctx, "input", r.input);
    if (r.shade >= 0) call(ctx, "setShadeMode", r.shade);
    if (r.key >= 0) call(ctx, "key", r.key);
    if (r.release >= 0) call(ctx, "inputRelease", r.release);
    if (r.key_up >= 0) call(ctx, "keyUp", r.key_up);
}

void glass_joy(uint32_t before, uint32_t now, glass_call_fn call, void* ctx) {
    static const uint32_t bits[] = {JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT, JOY_FIRE};
    static const int dirs[] = {0, 1, 2, 3, 5};
    for (int i = 0; i < 5; i++) {
        if ((before ^ now) & bits[i]) call(ctx, (now & bits[i]) ? "input" : "inputRelease", dirs[i]);
    }
}
