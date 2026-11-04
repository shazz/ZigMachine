/* KOS's C: on the board (bkosdrive.h): the request block, glass's answer, a timeout. */
#include "bkosdrive.h"

#include "bdinval.h"
#include "bkosreq.h"
#include "bmicros.h"
#include "glass_cart.h"
#include "glass_map.h"

#define KOS_DRIVE_ADDR (CART_CPU_BASE + DDR_CART_BYTES - KOS_DRIVE_FROM_TOP)
_Static_assert(KOS_DRIVE_FROM_TOP - KOS_DRIVE_WORDS * 4 >= CART_REQ_FROM_TOP, "the block is over the request block");
_Static_assert(KOS_DRIVE_FROM_TOP <= KOS_MEDIA_FROM_TOP - 4, "the block is over the media word");

static uint32_t g_seq;

/* `count` sectors of `unit` into the cart's memory at `dst`; the sectors read, 0 for none. glass
 * writes them into the window past this core's write-through D-cache: the lines of dst are
 * dropped after the answer, as the block's own lines are on every poll. */
uint32_t board_kos_drive_read(uint8_t* mem, uint64_t mem_size, uint32_t unit, uint32_t sector, uint32_t count,
                              uint32_t dst) {
    if (unit != KOS_DRIVE_UNIT_C || count == 0 || count > KOS_DRIVE_MAX_SECTORS) return 0;
    if (dst % 4 || (uint64_t)dst + (uint64_t)count * 512u > mem_size) return 0; /* host/disk.h's rules */
    uintptr_t at = (uintptr_t)(mem + dst);
    if (at < CART_CPU_BASE || at + count * 512u > CART_CPU_BASE + DDR_CART_BYTES) return 0;
    volatile uint32_t* w = (volatile uint32_t*)(uintptr_t)KOS_DRIVE_ADDR;
    uint32_t seq = ++g_seq ? g_seq : ++g_seq; /* never 0: a zeroed KD_ACK answers nothing */
    bkosreq_write(w, seq, unit, sector, count, (uint32_t)(at - CART_CPU_BASE));
    uint32_t t0 = board_micros();
    int32_t n;
    do {
        bdi_inval_line(KOS_DRIVE_ADDR + KD_DONE * 4);
        bdi_inval_line(KOS_DRIVE_ADDR + KD_ACK * 4);
        n = bkosreq_answer(w, seq);
    } while (n < 0 && board_micros() - t0 < KOS_DRIVE_TIMEOUT_MS * 1000u);
    w[KD_MAGIC] = 0; /* answered or abandoned: glass must not serve it again */
    if (n <= 0) return 0;
    zm_dflush(); /* the sectors landed past every line of dst */
    return (uint32_t)n;
}
