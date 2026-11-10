/* The network, MOCKED: a scripted telnet BBS inside the cart, behind the knet transport interface
 * (kestrel_net.h) that ZIGNIC's sockets will implement for real. It answers one host, fakebbs.zig
 * (10.0.0.2), on port 23; any other name does not resolve and any other address refuses.
 *
 * The script: the connect completes one frame later (so the caller's non-blocking connect path runs),
 * then the BBS opens the telnet negotiation (IAC WILL ECHO, WILL SGA, DO TTYPE, DO NAWS), asks the
 * terminal type when it is offered (SB TTYPE SEND), and once it has the type and the window size (or
 * after half a second) sends BBS.ANS off the cart's floppy (CP437 ANSI art), a line with what the
 * negotiation told it, and a prompt. From then on it echoes what is typed: Enter starts a new prompt line,
 * Backspace rubs out. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "kestrel_net.h"
#include "kestrel_fiber.h"
#include "kestrel_fakebbs.h"

#define BBS_IP 0x0a000002u
#define RXCAP 32768
enum { NEGOTIATE, ONLINE };
enum { IAC = 255, DONT = 254, DO = 253, WONT = 252, WILL = 251, SB = 250, SE = 240 };
enum { O_ECHO = 1, O_SGA = 3, O_TTYPE = 24, O_NAWS = 31 };

static struct peer {
    int state, phase;
    uint64_t open_at;
    uint8_t *rx;                     /* bytes on their way to the client */
    int rd, wr;
    uint8_t cmd[64];                 /* the telnet command being parsed from the client */
    int ncmd, last_cr;
    char ttype[33];
    int cols, rows;
} peers[KNET_SOCKETS];
static unsigned typed;               /* data bytes the client sent (the harness reads it) */

static void out(struct peer *p, const void *b, int n)
{
    if (p->wr + n > RXCAP && p->rd) { memmove(p->rx, p->rx + p->rd, (size_t)(p->wr - p->rd)); p->wr -= p->rd; p->rd = 0; }
    if (p->wr + n > RXCAP) n = RXCAP - p->wr;
    memcpy(p->rx + p->wr, b, (size_t)n);
    p->wr += n;
}
static void outs(struct peer *p, const char *s) { out(p, s, (int)strlen(s)); }

static void send_screen(struct peer *p)
{
    FILE *f = fopen("/BBS.ANS", "rb");
    if (f) {
        uint8_t buf[512];
        size_t n;
        while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
            uint8_t *eof = memchr(buf, 0x1a, n);       /* a SAUCE record follows ^Z: not for the screen */
            out(p, buf, (int)(eof ? (size_t)(eof - buf) : n));
            if (eof) break;
        }
        fclose(f);
    } else {
        outs(p, "\x1b[2J\x1b[1;31mfakebbs: BBS.ANS is not on this disk.\x1b[0m\r\n");
    }
    char line[160];
    snprintf(line, sizeof line, "\x1b[0m\r\n\x1b[1;36mtelnet: terminal %s, %dx%d\x1b[0m\r\n\x1b[1;33m> \x1b[0;37m",
             p->ttype[0] ? p->ttype : "(none)", p->cols, p->rows);
    outs(p, line);
    p->phase = ONLINE;
}

static void opened(struct peer *p)
{
    static const uint8_t hello[] = { IAC, WILL, O_ECHO, IAC, WILL, O_SGA, IAC, DO, O_TTYPE, IAC, DO, O_NAWS };
    p->state = KNET_OPEN;
    out(p, hello, sizeof hello);
}

/* Lazy time: the connect completes, and the negotiation gives up waiting, when the caller looks. */
static void advance(struct peer *p)
{
    uint64_t now = kfib_now_us();
    if (p->state == KNET_CONNECTING && now > p->open_at) opened(p);
    if (p->state == KNET_OPEN && p->phase == NEGOTIATE && now >= p->open_at + 500000) send_screen(p);
}

static void command(struct peer *p)
{
    uint8_t *c = p->cmd;
    if (c[1] == WILL && c[2] == O_TTYPE) { static const uint8_t ask[] = { IAC, SB, O_TTYPE, 1, IAC, SE }; out(p, ask, sizeof ask); }
    if (c[1] == SB && c[2] == O_TTYPE && c[3] == 0) {
        int n = p->ncmd - 6 < 32 ? p->ncmd - 6 : 32;
        memcpy(p->ttype, c + 4, (size_t)(n > 0 ? n : 0));
        p->ttype[n > 0 ? n : 0] = 0;
    }
    if (c[1] == SB && c[2] == O_NAWS && p->ncmd >= 9) { p->cols = c[3] << 8 | c[4]; p->rows = c[5] << 8 | c[6]; }
    if (p->phase == NEGOTIATE && p->ttype[0] && p->cols) send_screen(p);
}

static int cmd_done(const struct peer *p)
{
    if (p->ncmd < 2) return 0;
    if (p->cmd[1] == SB) return p->ncmd >= 4 && p->cmd[p->ncmd - 2] == IAC && p->cmd[p->ncmd - 1] == SE;
    if (p->cmd[1] >= WILL) return p->ncmd == 3;
    return 1;                                       /* a two-byte command (NOP, AYT, ...) */
}

static void echo(struct peer *p, uint8_t ch)
{
    typed++;
    if (p->last_cr && (ch == 0 || ch == '\n')) { p->last_cr = 0; return; }   /* telnet's CR NUL / CR LF */
    p->last_cr = ch == '\r';
    if (ch == '\r') outs(p, "\r\n\x1b[1;33m> \x1b[0;37m");
    else if (ch == 8 || ch == 127) outs(p, "\b \b");
    else if (ch >= 32) out(p, &ch, 1);
}

static void from_client(struct peer *p, const uint8_t *b, int n)
{
    for (int i = 0; i < n; i++) {
        if (p->ncmd || b[i] == IAC) {
            if (p->ncmd == 1 && b[i] == IAC) { p->ncmd = 0; echo(p, IAC); continue; }   /* IAC IAC: a 255 */
            if (p->ncmd < (int)sizeof p->cmd) p->cmd[p->ncmd++] = b[i];
            if (cmd_done(p)) { command(p); p->ncmd = 0; }
            continue;
        }
        if (p->phase == ONLINE) echo(p, b[i]);
    }
}

static int f_resolve(const char *host, uint32_t *ip)
{
    if (strcasecmp(host, "fakebbs.zig") != 0) return -1;
    *ip = BBS_IP;
    return 0;
}
static int f_open(int s, uint32_t ip, uint16_t port)
{
    struct peer *p = &peers[s];
    uint8_t *rx = p->rx ? p->rx : malloc(RXCAP);
    memset(p, 0, sizeof *p);
    p->rx = rx;
    if (!rx) return -1;
    p->state = ip == BBS_IP && port == 23 ? KNET_CONNECTING : KNET_REFUSED;
    p->open_at = kfib_now_us();
    return 0;
}
static int f_state(int s) { advance(&peers[s]); return peers[s].state; }
static int f_rx_avail(int s) { advance(&peers[s]); return peers[s].wr - peers[s].rd; }
static int f_rx(int s, void *buf, int len, int peek)
{
    struct peer *p = &peers[s];
    int n = p->wr - p->rd < len ? p->wr - p->rd : len;
    memcpy(buf, p->rx + p->rd, (size_t)n);
    if (!peek) p->rd += n;
    return n;
}
static int f_tx_room(int s) { return peers[s].state == KNET_OPEN ? 4096 : 0; }
static int f_tx(int s, const void *buf, int len) { from_client(&peers[s], buf, len); return len; }
static void f_close(int s) { if (peers[s].state != KNET_REFUSED) peers[s].state = KNET_CLOSED; }

unsigned kestrel_fakebbs_typed(void) { return typed; }

static const struct knet_transport fakebbs = { "mock", f_resolve, f_open, f_state, f_rx_avail, f_rx, f_tx_room, f_tx, f_close };
const struct knet_transport *knet = &fakebbs;
