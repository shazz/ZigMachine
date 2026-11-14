/* env.hwAstro on the board (SPIKE, docs/ARM_FPU_COPROC.md): ASTROLABE's descriptors handed to
 * the ARM's VFPv3 over the mailbox (soc/zm_astro.py), the machine's own code (soft f64 on ZIGGY)
 * when nobody serves them. The board link wraps the machine's export
 * (-Wl,--wrap=w2c_machine_hwAstro, cycles/board.mk), as bblit.c wraps hwBlit.
 *
 * The protocol is bastro_post.h's: the descriptors' input words into the RAM, COUNT and the
 * cart memory's place, then SEQ (an IO store, so after every posted DDR store: the cart's
 * arrays are in DDR when the ARM sees it), TAKEN, DONE, the results back. Here: whether the
 * bitstream has the mailbox at all (STATUS.ASTRO, read once at boot), the D-cache dropped after
 * an array op (the ARM wrote DDR behind it), and W_CYCLES = the call's ZIGGY cycles in every
 * descriptor, served or not, so a cart can time the coprocessor against its own fallback. */
#include "bastro.h"

#include "bastro_post.h"
#include "bmicros.h"
#include "board.h"
#include "dflush.h"
#include "glass_map.h" /* CART_CPU_BASE */
#include "vboard.h"    /* zmv_status, ZMV_BIT */

struct w2c_machine;
uint32_t __real_w2c_machine_hwAstro(struct w2c_machine* m, uint32_t desc, uint32_t count);
uint32_t __wrap_w2c_machine_hwAstro(struct w2c_machine* m, uint32_t desc, uint32_t count);

static bastro_ctx g_ctx;
static int g_on; /* the bitstream has the mailbox */
bastro_stats bastro;

void bastro_boot(uint8_t* mem, uint64_t size) {
    g_ctx = (bastro_ctx){
        .box = (volatile uint32_t*)(uintptr_t)ASTRO_WINDOW,
        .mem = mem,
        .size = size > 0xFFFFFFFFu ? 0xFFFFFFFFu : (uint32_t)size,
        .mem_off = (uint32_t)((uintptr_t)mem - CART_CPU_BASE),
        .micros = board_micros,
    };
    g_on = (zmv_status() & ZMV_BIT(ASTRO)) != 0;
}

uint32_t __wrap_w2c_machine_hwAstro(struct w2c_machine* m, uint32_t desc, uint32_t count) {
    uint32_t t0 = board_cycles();
    uint32_t r = g_on ? bastro_post(&g_ctx, desc, count) : BASTRO_UNSERVED;
    int served = r != BASTRO_UNSERVED;
    if (!served) r = __real_w2c_machine_hwAstro(m, desc, count);
    else if (g_ctx.arrays) zm_dflush(); /* the ARM's results are in DDR behind the D-cache */
    uint32_t dt = board_cycles() - t0;
    if (bastro_list_ok(&g_ctx, desc, count))
        for (uint32_t i = 0; i < count; i++) bastro_wr(&g_ctx, desc + i * ASTRO_DESC_WORDS * 4 + 4 * ASTRO_W_CYCLES, dt);
    bastro.calls++;
    bastro.served += served;
    bastro.cycles += dt;
    bastro.untaken = g_ctx.untaken;
    bastro.timeouts = g_ctx.timeouts;
    bastro.arm_ns = g_ctx.arm_ns;
    return r;
}
