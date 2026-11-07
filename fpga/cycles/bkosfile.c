/* KOS's C: writes on the board (bkosfile.h): the cart's request (rom/kos/kfs_abi.zig, 12 words in its
 * memory) bounded as the page bounds it (docs/kos-cfile.js), its addresses turned into window offsets,
 * the block written, glass's answer awaited. A write remounts the card and syncs it: seconds, not the
 * sector block's half millisecond (KOS_FILE_TIMEOUT_MS). The `gen` operation is answered here, from the
 * word glass bumps after each write: no round trip. */
#include "bkosfile.h"

#include <string.h>

#include "bdinval.h"
#include "bkosfreq.h"
#include "bmicros.h"
#include "glass_cart.h"
#include "glass_map.h"

#define KOS_FILE_ADDR (CART_CPU_BASE + DDR_CART_BYTES - KOS_FILE_FROM_TOP)
#define KOS_CGEN_ADDR (CART_CPU_BASE + DDR_CART_BYTES - KOS_CGEN_FROM_TOP)
_Static_assert(KOS_FILE_FROM_TOP - KOS_FILE_WORDS * 4 >= KOS_DRIVE_FROM_TOP, "the block is over the sector block");
_Static_assert(KOS_FILE_FROM_TOP <= KOS_CGEN_FROM_TOP - 4, "the block is over the generation word");
_Static_assert(KOS_CGEN_FROM_TOP <= KOS_MEDIA_FROM_TOP - 4, "the generation word is over the media word");

#define ERANGE_TOS ((uint32_t)-64)
#define EWRITF_TOS ((uint32_t)-10)
#define EWRPRO_TOS ((uint32_t)-13)

static uint32_t g_seq;

static uint32_t gen(void) {
    bdi_inval_line(KOS_CGEN_ADDR);
    return *(volatile uint32_t*)(uintptr_t)KOS_CGEN_ADDR;
}

/* Cart address `a`, `n` bytes long, as a window offset; 0xFFFFFFFF if any of it lies outside. */
static uint32_t window_off(uint8_t* mem, uint64_t mem_size, uint32_t a, uint32_t n) {
    if ((uint64_t)a + n > mem_size) return 0xFFFFFFFFu;
    uintptr_t at = (uintptr_t)(mem + a);
    if (at < CART_CPU_BASE || at + n > CART_CPU_BASE + DDR_CART_BYTES - KOS_FILE_FROM_TOP) return 0xFFFFFFFFu;
    return (uint32_t)(at - CART_CPU_BASE);
}

uint32_t board_kos_file_op(uint8_t* mem, uint64_t mem_size, uint32_t req) {
    if (req % 4 || (uint64_t)req + 48 > mem_size) return ERANGE_TOS;
    uint32_t r[12];
    memcpy(r, mem + req, sizeof r);
    if (r[0] == 0) { /* the generation */
        uint32_t g = gen();
        memcpy(mem + req + 44, &g, 4);
        return g & 0x7FFFFFFFu;
    }
    if (r[8] > KOS_FILE_PATH_MAX || r[10] > KOS_FILE_PATH_MAX || r[5] > KOS_FILE_DATA_MAX) return ERANGE_TOS;
    uint32_t data = window_off(mem, mem_size, r[6], r[5]);
    uint32_t path = window_off(mem, mem_size, r[7], r[8]);
    uint32_t path2 = window_off(mem, mem_size, r[9], r[10]);
    if (data == 0xFFFFFFFFu || path == 0xFFFFFFFFu || path2 == 0xFFFFFFFFu) return ERANGE_TOS;
    const uint32_t f[KF_FIELDS] = {r[0], r[1], r[2], r[3], r[4], r[5], data, path, r[8], path2, r[10]};
    volatile uint32_t* w = (volatile uint32_t*)(uintptr_t)KOS_FILE_ADDR;
    uint32_t seq = ++g_seq ? g_seq : ++g_seq; /* never 0: a zeroed KF_ACK answers nothing */
    bkosfreq_write(w, seq, f);
    uint32_t t0 = board_micros(), n;
    int taken = 0;
    do {
        bdi_inval_line(KOS_FILE_ADDR + KF_DONE * 4); /* KF_DONE and KF_ACK share a line */
        bdi_inval_line(KOS_FILE_ADDR + KF_TAKEN * 4); /* KF_TAKEN starts the next one */
        n = bkosfreq_answer(w, seq);
        taken = taken || bkosfreq_taken(w, seq);
        if (!taken && board_micros() - t0 >= KOS_FILE_TAKE_MS * 1000u) break; /* nobody serves this block */
    } while (n == BKOSF_WAIT && board_micros() - t0 < KOS_FILE_TIMEOUT_MS * 1000u);
    w[KF_MAGIC] = 0; /* answered or abandoned: glass must not serve it again */
    if (n == BKOSF_WAIT && !taken) return EWRPRO_TOS; /* no glass (or another layout's): nothing was written */
    uint32_t g = gen();
    memcpy(mem + req + 44, &g, 4);
    return n == BKOSF_WAIT ? EWRITF_TOS : n; /* no answer in time: the write may be half done */
}
