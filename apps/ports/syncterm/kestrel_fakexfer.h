/* kestrel_fakexfer.c: the in-cart BBS's file SENDER (XMODEM-1K, YMODEM), for the download harness. */
#ifndef KESTREL_FAKEXFER_H
#define KESTREL_FAKEXFER_H
#include <stdint.h>

enum { XF_XMODEM = 'X', XF_YMODEM = 'Y', XF_YMODEM2 = 'W', XF_CANCEL = 'K' };
#define XF_NAME "TEST.BIN"
#define XF_SIZE 2500

struct xfer { int kind, st, blk, last, variant, len, cans; uint8_t buf[1030]; };

/* The file the BBS offers: byte i = (i * 167 + 13 + 41 * variant) & 255, with CR NUL 255 255 at 300 (what telnet
 * would mangle without binary mode and IAC doubling); apps/harness/syncterm_download.mjs builds the same bytes. */
uint8_t kestrel_xfer_byte(int variant, int i);
/* Begin a send of `kind` (XF_*); the sender then waits for the receiver's 'C'. */
void kestrel_xfer_start(struct xfer *x, int kind);
int kestrel_xfer_active(const struct xfer *x);
typedef void (*kestrel_xfer_emit)(void *, const uint8_t *, int);   /* takes the bytes to send back to the receiver */
/* The prompt line `c` (X, Y, W, K, either case): the BBS announces the file and starts sending it. 0: not a command. */
int kestrel_xfer_line(struct xfer *x, int c, kestrel_xfer_emit emit, void *ctx);
/* One byte from the receiver. 1 when that ended the transfer (the BBS shows its prompt again). */
int kestrel_xfer_in(struct xfer *x, uint8_t b, kestrel_xfer_emit emit, void *ctx);
#endif
