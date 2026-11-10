/* SyncTERM's sockets over ZIGNIC (docs/GEM_NET.md, machine/sdk/net_abi.zig): the second knet transport
 * (kestrel_net.h). The card does TCP/IP and DNS (glass on the board, the page's ?net=peer, ...); this only opens
 * card sockets, polls them and copies bytes. Routing per socket: "fakebbs.zig" (and its address) stays on the
 * in-cart BBS (kestrel_fakebbs.c), anything else goes to the card. With no card (the page without ?net=, a sim)
 * every socket is the fake one, as before: the gate's pins do not move. */
#include <stdint.h>
#include <string.h>
#include <strings.h>

#include "kestrel_fiber.h"
#include "kestrel_net.h"

__attribute__((import_module("env"), import_name("netOp"))) extern int32_t netOp(uint32_t req);

extern const struct knet_transport knet_fake; /* kestrel_fakebbs.c */
#define FAKE_IP 0x0A000002u                   /* kestrel_fakebbs.c BBS_IP (10.0.0.2): what "fakebbs.zig" resolves to */

enum { OP_INFO = 0, OP_OPEN = 1, OP_CONNECT = 2, OP_SEND = 4, OP_RECV = 5, OP_POLL = 7, OP_CLOSE = 8, OP_RESOLVE = 9 };
enum { MODE_TCP = 1, MODE_RESOLVE = 5 };
enum { ST_CONNECTING = 2, ST_ESTABLISHED = 3, ST_CLOSE_WAIT = 5, ST_RESOLVED = 7, ST_FAILED = 8 };
#define ID_ZNIC 0x5A4E4943u
#define STAGE 4096

struct req { uint32_t op, sock, a0, a1, buf, len, host, host_len, state, events, err, peer_ip, peer_port, local_port, r0, r1; };

static int card = -1;          /* -1 not asked yet, 0 none, 1 a card answers */
static int zs[KNET_SOCKETS];   /* the card's socket for shim socket s, -1 none */
static uint8_t fake[KNET_SOCKETS];
static uint8_t stage[KNET_SOCKETS][STAGE];
static int st_rd[KNET_SOCKETS], st_wr[KNET_SOCKETS];

static int32_t op(struct req *r) { return netOp((uint32_t)(uintptr_t)r); }

int kestrel_zignic_present(void)
{
    if (card < 0) {
        uint32_t info[6] = {0};
        struct req r = { .op = OP_INFO, .buf = (uint32_t)(uintptr_t)info, .len = sizeof info };
        card = op(&r) == 1 && info[0] == ID_ZNIC;
        for (int i = 0; i < KNET_SOCKETS; i++) zs[i] = -1;
    }
    return card;
}

static int32_t poll_sock(int z, struct req *r)
{
    memset(r, 0, sizeof *r);
    r->op = OP_POLL;
    r->sock = (uint32_t)z;
    op(r);
    return (int32_t)r->state;
}

static int resolved(void *p)
{
    struct req r;
    int s = poll_sock((int)(intptr_t)p, &r);
    return s == ST_RESOLVED || s == ST_FAILED;
}

static int z_resolve(const char *host, uint32_t *ip)
{
    if (!kestrel_zignic_present() || strcasecmp(host, "fakebbs.zig") == 0) return knet_fake.resolve(host, ip);
    struct req r = { .op = OP_OPEN, .a0 = MODE_RESOLVE };
    int z = op(&r);
    if (z < 0) return -1;
    r = (struct req){ .op = OP_RESOLVE, .sock = (uint32_t)z, .host = (uint32_t)(uintptr_t)host, .host_len = (uint32_t)strlen(host) };
    op(&r);
    kfib_block(resolved, (void *)(intptr_t)z, kfib_now_us() + 4000000);
    int ok = poll_sock(z, &r) == ST_RESOLVED;
    if (ok) *ip = r.peer_ip;
    r = (struct req){ .op = OP_CLOSE, .sock = (uint32_t)z };
    op(&r);
    return ok ? 0 : -1;
}

static int z_open(int s, uint32_t ip, uint16_t port)
{
    st_rd[s] = st_wr[s] = 0;
    fake[s] = !kestrel_zignic_present() || ip == FAKE_IP;
    if (fake[s]) return knet_fake.open(s, ip, port);
    struct req r = { .op = OP_OPEN, .a0 = MODE_TCP };
    zs[s] = op(&r);
    if (zs[s] < 0) return -1;
    r = (struct req){ .op = OP_CONNECT, .sock = (uint32_t)zs[s], .a0 = ip, .a1 = port };
    int32_t c = op(&r);
    return c == 0 || c == -4 ? 0 : -1; /* established at once, or in progress (Err.again) */
}

static void fill(int s)
{
    if (st_rd[s] < st_wr[s] || zs[s] < 0) return;
    struct req r = { .op = OP_RECV, .sock = (uint32_t)zs[s], .buf = (uint32_t)(uintptr_t)stage[s], .len = STAGE };
    int32_t n = op(&r);
    st_rd[s] = 0;
    st_wr[s] = n > 0 ? n : 0;
}

static int z_state(int s)
{
    if (fake[s]) return knet_fake.state(s);
    if (zs[s] < 0) return KNET_CLOSED;
    struct req r;
    switch (poll_sock(zs[s], &r)) {
    case ST_CONNECTING: return KNET_CONNECTING;
    case ST_ESTABLISHED: return KNET_OPEN;
    case ST_CLOSE_WAIT: fill(s); return st_rd[s] < st_wr[s] ? KNET_OPEN : KNET_CLOSED;
    case ST_FAILED: return KNET_REFUSED;
    default: return KNET_CLOSED;
    }
}

static int z_rx_avail(int s)
{
    if (fake[s]) return knet_fake.rx_avail(s);
    fill(s);
    return st_wr[s] - st_rd[s];
}

static int z_rx(int s, void *buf, int len, int peek)
{
    if (fake[s]) return knet_fake.rx(s, buf, len, peek);
    fill(s);
    int n = st_wr[s] - st_rd[s] < len ? st_wr[s] - st_rd[s] : len;
    memcpy(buf, stage[s] + st_rd[s], (size_t)n);
    if (!peek) st_rd[s] += n;
    return n;
}

static int z_tx_room(int s) { return fake[s] ? knet_fake.tx_room(s) : z_state(s) == KNET_OPEN ? 4096 : 0; }

static int z_tx(int s, const void *buf, int len)
{
    if (fake[s]) return knet_fake.tx(s, buf, len);
    struct req r = { .op = OP_SEND, .sock = (uint32_t)zs[s], .buf = (uint32_t)(uintptr_t)buf, .len = (uint32_t)len };
    int32_t n = op(&r);
    return n > 0 ? n : 0;
}

static void z_disconnect(int s)
{
    if (fake[s]) { knet_fake.disconnect(s); return; }
    if (zs[s] >= 0) {
        struct req r = { .op = OP_CLOSE, .sock = (uint32_t)zs[s] };
        op(&r);
        zs[s] = -1;
    }
}

static const struct knet_transport zignic = { "zignic", z_resolve, z_open, z_state, z_rx_avail, z_rx, z_tx_room, z_tx, z_disconnect };
const struct knet_transport *knet = &zignic;
