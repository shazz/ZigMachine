/* KESTREL-only "hello world": a lean cart written for ZIGGY itself, not compiled from wasm
 * (cycles/native/native.mk, decisions.md 2026-10-17). The browser cannot run it.
 *
 * It is called exactly as a wasm2c cart is (bsys.c): bind(table), instantiate(cart, env),
 * boot(cart), skip_boot(cart), then frame(cart, dt) and plane_enabled(cart, p) every frame.
 * `cart` is this file's own instance struct (the system calloc's inst_bytes of it); `env` is
 * the system's, which every table call into the machine or the ROM takes first. The shared
 * memory (registers, palettes, planes, the cart window) is the one the wasm carts see: the
 * table's w2c_env_memory(env)->data is its byte 0, and the ROM reads text from it, so the
 * string is copied there (to the cart window's base, the RAM this cart declares it owns). */
#include <stdint.h>

#include "native.h"

typedef struct w2c_cart {
    struct w2c_env* env;
    uint8_t* mem;  /* the shared memory's byte 0 */
    uint32_t gui;  /* the ROM's drawing context over plane 0 */
    uint32_t frames;
} hello;

static const char MSG[] = "HELLO WORLD";
#define MSG_LEN (sizeof MSG - 1)

const zm_sys_table* zm_sys; /* .bss: the system zeroes it, then bind() fills it */

static void bind(const zm_sys_table* t) { zm_sys = t; }

static void instantiate(hello* c, struct w2c_env* e) {
    c->env = e;
    c->mem = *(uint8_t**)SYS(ZM_RT_w2c_env_memory, void* (*)(struct w2c_env*))(e); /* ->data: offset 0 */
}

static void boot(hello* c) {
    struct w2c_env* e = c->env;
    uint32_t video = SYS(ZM_ENV_hwVideoBase, uint32_t (*)(struct w2c_env*))(e);
    *(volatile uint32_t*)(c->mem + video + NATIVE_REG_BACKGROUND) = NATIVE_BORDER_RGBA;
    for (uint32_t i = 0; i < MSG_LEN; i++) c->mem[NATIVE_TEXT_AT + i] = (uint8_t)MSG[i];
    c->gui = SYS(ZM_ENV_guiOpenPlane, uint32_t (*)(struct w2c_env*, uint32_t, uint32_t, uint32_t))(e, 0, 320, 200);
    SYS(ZM_ENV_romInstallPalettePlane, void (*)(struct w2c_env*, uint32_t))(e, 0); /* GEM's 0 black, 1 white */
}

static void skip_boot(hello* c) { (void)c; }

/* Plane 0 black, the text white, bouncing 64 px left and right so a frozen frame shows. */
static void frame(hello* c, float dt) {
    (void)dt;
    struct w2c_env* e = c->env;
    if (!c->gui) return; /* the ROM gave no context: plane 0 stays off */
    uint32_t t = c->frames++ & 127u;
    uint32_t x = 116u + (t < 64u ? t : 127u - t) - 32u;
    SYS(ZM_ENV_guiRect, void (*)(struct w2c_env*, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t))(
        e, c->gui, 0, 0, 320, 200, GEM_BLACK);
    SYS(ZM_ENV_guiText, void (*)(struct w2c_env*, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                 uint32_t))(e, c->gui, NATIVE_TEXT_AT, MSG_LEN, x, 96, GEM_WHITE, GEM_BLACK);
}

static uint32_t plane_enabled(hello* c, uint32_t p) { return p == 0 && c->gui != 0; }

static void hbl_dispatch(hello* c, uint32_t id, uint32_t plane, uint32_t line, uint32_t x) {
    (void)c, (void)id, (void)plane, (void)line, (void)x;
}

extern char __cart_bss_start[], __cart_bss_end[]; /* cycles/cart.ld */

__attribute__((section(".zm_cart_hdr"), used)) const zm_cart_hdr zm_cart_header = {
    .magic = ZM_CART_HDR_MAGIC, .version = ZM_SYS_ABI_VERSION, .hdr_bytes = sizeof(zm_cart_hdr),
    .bss_start = __cart_bss_start, .bss_end = __cart_bss_end, .pages = NATIVE_PAGES,
    .cart_high = NATIVE_CART_HIGH, .inst_bytes = sizeof(hello), .bind = bind, .instantiate = instantiate,
    .boot = boot, .skip_boot = skip_boot, .frame = frame, .plane_enabled = plane_enabled,
    .hbl_dispatch = hbl_dispatch, NATIVE_NO_BRIDGES, .tag = "hello",
};
