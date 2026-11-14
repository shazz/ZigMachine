/* ZIGNIC on the board (bnet.h): the cart's Req (machine/sdk/net_abi.zig, 16 words in its memory) bounded as the
 * page bounds it (docs/net-host.js), its buffer and host name turned into window offsets, the NET block written,
 * glass's answer awaited (glass never blocks on a socket, so it answers within its poll, < 1 ms), then the
 * socket's state, events, error and peer copied back into the Req. No glass, an old glass, or no answer in
 * NET_TIMEOUT_MS: no_card (-1), as a host without a card answers. */
#include "bnet.h"

#include <string.h>

#include "bdinval.h"
#include "bmicros.h"
#include "bnetreq.h"
#include "glass_cart.h"
#include "glass_map.h"

#define NET_ADDR (CART_CPU_BASE + DDR_CART_BYTES - NET_FROM_TOP)
_Static_assert(NET_FROM_TOP - NET_WORDS * 4 >= KOS_FILE_FROM_TOP, "the NET block is over the C: file block");
_Static_assert(NET_FROM_TOP > DISK_DESC_FROM_TOP && NET_FROM_TOP <= 0x1000, "the NET block is below the disk descriptor, in the top 4 KiB");

#define ERR_NO_CARD ((uint32_t)-1)
#define ERR_INVALID ((uint32_t)-3)
#define REQ_WORDS 16
#define IO_MAX 16384u
#define HOST_MAX 255u

static uint32_t g_seq;

/* Cart address `a`, `n` bytes long, as a window offset; 0xFFFFFFFF if any of it lies outside. n = 0: offset 0. */
static uint32_t window_off(uint8_t* mem, uint64_t mem_size, uint32_t a, uint32_t n) {
    if (n == 0) return 0;
    if ((uint64_t)a + n > mem_size) return 0xFFFFFFFFu;
    uintptr_t at = (uintptr_t)(mem + a);
    if (at < CART_CPU_BASE || at + n > CART_CPU_BASE + DDR_CART_BYTES - 0x1000) return 0xFFFFFFFFu;
    return (uint32_t)(at - CART_CPU_BASE);
}

static uint32_t wait_answer(volatile uint32_t* w, uint32_t seq) {
    uint32_t t0 = board_micros();
    for (;;) {
        bdi_inval_line(NET_ADDR + NB_DONE * 4); /* NB_DONE, NB_ACK and NB_OUT share the block's lines */
        bdi_inval_line(NET_ADDR + NB_OUT * 4);
        bdi_inval_line(NET_ADDR + (NB_OUT + NB_OUT_WORDS - 1) * 4);
        if (bnetreq_answered(w, seq)) return 1;
        if (board_micros() - t0 >= NET_TIMEOUT_MS * 1000u) return 0;
    }
}

uint32_t board_net_op(uint8_t* mem, uint64_t mem_size, uint32_t req) {
    if (req % 4 || (uint64_t)req + REQ_WORDS * 4 > mem_size) return ERR_INVALID;
    uint32_t r[REQ_WORDS];
    memcpy(r, mem + req, sizeof r);
    uint32_t len = r[5] > IO_MAX ? IO_MAX : r[5];
    if (r[7] > HOST_MAX) return ERR_INVALID;
    uint32_t buf = window_off(mem, mem_size, r[4], len);
    uint32_t host = window_off(mem, mem_size, r[6], r[7]);
    if (buf == 0xFFFFFFFFu || host == 0xFFFFFFFFu) return ERR_INVALID;
    const uint32_t f[NB_FIELDS] = {r[0], r[1], r[2], r[3], buf, len, host, r[7]};
    volatile uint32_t* w = (volatile uint32_t*)(uintptr_t)NET_ADDR;
    uint32_t seq = ++g_seq ? g_seq : ++g_seq; /* never 0: a zeroed NB_ACK answers nothing */
    bnetreq_write(w, seq, f);
    int ok = wait_answer(w, seq);
    w[NB_MAGIC] = 0; /* answered or abandoned: glass must not serve it again */
    if (!ok) return ERR_NO_CARD;
    /* glass wrote the cart's recv bytes through HP0, past this D$: drop the lines the buffer covers. */
    if (len) for (uintptr_t a = (uintptr_t)(mem + r[4]) & ~(uintptr_t)31; a < (uintptr_t)(mem + r[4] + len); a += 32) bdi_inval_line(a);
    uint32_t out[NB_OUT_WORDS];
    for (int i = 0; i < NB_OUT_WORDS; i++) out[i] = w[NB_OUT + i];
    memcpy(mem + req + 8 * 4, out, sizeof out);
    return w[NB_DONE];
}
