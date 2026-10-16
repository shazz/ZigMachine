/* The system image's side of the board's split (decisions.md 2026-10-15): find the lean cart
 * image ZWINDOW placed at ZM_CART_IMG_AT, refuse one built for another table version, bind it,
 * and boot the three modules exactly as host/boot.c does in the monolithic image, the cart
 * through its header. Lines (sim): "ZM CART tag table a.b", or "ZM CART none at addr" /
 * "ZM CARTABI need a.b have c.d" and the run ends (CART_TRAPPED with TRAP_NO_CART /
 * TRAP_CART_ABI on the board, which glass names on the OSD). */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bdisk.h"
#include "board.h"
#include "boot.h"
#include "bsys.h"
#include "bsys_abi.h"
#include "glass_cart.h"
#include "glass_map.h"

extern const zm_sys_table zm_sys_table_v; /* tools/host_split.py's sys_env.c */
const zm_cart_hdr* zm_cart;

_Static_assert(ZM_CART_IMG_AT == CART_IMG_AT, "sys_abi.txt and map_cart.zig disagree on the cart's place");

wasm_rt_memory_t* w2c_env_memory(struct w2c_env* e) { return &e->memory; }

static void refuse(const char* why, uint32_t need, uint32_t code) {
    printf("ZM CARTABI %s need %lu.%lu have %lu.%lu\n", why, (unsigned long)(need >> 16),
           (unsigned long)(need & 0xFFFFu), (unsigned long)ZM_SYS_ABI_MAJOR, (unsigned long)ZM_SYS_ABI_MINOR);
    board_finish((int)code);
}

void bsys_link(void) {
    const zm_cart_hdr* h = (const zm_cart_hdr*)(uintptr_t)(CART_CPU_BASE + ZM_CART_IMG_AT);
    if (h->magic != ZM_CART_HDR_MAGIC) {
        printf("ZM CART none at %08lx\n", (unsigned long)(uintptr_t)h);
        board_finish((int)TRAP_NO_CART);
    }
    if (!bsys_abi_ok(h->version, ZM_SYS_ABI_VERSION)) refuse("table", h->version, TRAP_CART_ABI);
    if (h->hdr_bytes != sizeof *h || h->pages != host_pages) refuse("header", h->version, TRAP_CART_ABI);
    memset(h->bss_start, 0, (size_t)(h->bss_end - h->bss_start)); /* crt0's job, cold or warm */
    zm_cart = h;
    bdisk_image_end = (uint32_t)(uintptr_t)h->bss_end - CART_CPU_BASE;
    h->bind(&zm_sys_table_v);
    printf("ZM CART %s table %lu.%lu\n", h->tag, (unsigned long)(h->version >> 16),
           (unsigned long)(h->version & 0xFFFFu));
}

/* host/boot.c's order (scene_hash.mjs boot()), the cart instance calloc'd at its own size. */
void host_boot(struct w2c_env* e) {
    wasm_rt_allocate_memory(&e->memory, host_pages, host_pages, false, WASM_DEFAULT_PAGE_SIZE);
    wasm2c_machine_instantiate(&e->machine, e);
    wasm2c_rom_instantiate(&e->rom, e);
    w2c_machine_hwSetRomHigh(&e->machine, host_rom_high);
    e->cart = calloc(1, zm_cart->inst_bytes);
    if (!e->cart) wasm_rt_trap(WASM_RT_TRAP_OOB);
    zm_cart->instantiate(e->cart, e);
    w2c_machine_hwSetCartHigh(&e->machine, host_cart_high);
    w2c_machine_hwInit(&e->machine);
    zm_cart->boot(e->cart);
    zm_cart->skip_boot(e->cart);
}

/* host/boot.c's, for the cart's --call table (ZM_MODES). */
u32 host_to_i32(double x) {
    if (!isfinite(x)) return 0;
    double m = fmod(trunc(x), 4294967296.0);
    if (m < 0) m += 4294967296.0;
    return (u32)m;
}

int host_call(struct w2c_env* e, const char* name, const double* args, int n) {
    double full[HOST_MAX_ARGS];
    for (int i = 0; i < HOST_MAX_ARGS; i++) full[i] = i < n ? args[i] : NAN;
    for (const host_export* x = host_exports; x->name; x++) {
        if (strcmp(x->name, name) == 0) {
            x->fn(e, full);
            return 0;
        }
    }
    fprintf(stderr, "host: cart has no export %s\n", name);
    return -1;
}
