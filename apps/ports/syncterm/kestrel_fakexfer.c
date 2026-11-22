/* The fake BBS's file sender (kestrel_fakebbs.c hands it the bytes SyncTERM sends once a transfer was started
 * by typing X / Y / W / K at the prompt): XMODEM with 1K blocks, YMODEM batch of one file, both CRC-16, driven
 * only by what the receiver sends (C, ACK, NAK), so it needs no clock. K is an XMODEM the sender abandons
 * after two blocks (CAN x5): the cancelled-download case. W is YMODEM again, a different content under the
 * same name: the name collision. Bytes go out through `emit`, which doubles telnet's 255. */
#include <stdio.h>
#include <string.h>
#include "kestrel_fakexfer.h"

enum { SOH = 1, STX = 2, EOT = 4, ACK = 6, NAK = 21, CAN = 24, SUB = 26 };
enum { START, DATA_ACK, EOT_ACK, HDR_ACK, DATA_C, END_C, END_ACK, DONE };
typedef kestrel_xfer_emit emit_fn;
void kestrel_log(const char *m);

uint8_t kestrel_xfer_byte(int variant, int i)
{
    static const uint8_t at300[4] = { 13, 0, 255, 255 };
    if (i >= 300 && i < 304) return at300[i - 300];
    return (uint8_t)(i * 167 + 13 + 41 * variant);
}

static unsigned crc16(const uint8_t *p, int n)
{
    unsigned c = 0;
    while (n--) { c ^= (unsigned)*p++ << 8; for (int k = 0; k < 8; k++) c = c & 0x8000 ? (c << 1) ^ 0x1021 : c << 1; }
    return c & 0xffff;
}

/* Block `blk` of the file (1K, padded with ^Z), or the header block 0 (128 bytes, YMODEM). */
static void put_block(struct xfer *x, int blk, int hdr, emit_fn emit, void *ctx)
{
    int n = hdr ? 128 : 1024;
    x->buf[0] = hdr ? SOH : STX, x->buf[1] = (uint8_t)blk, x->buf[2] = (uint8_t)~blk;
    memset(x->buf + 3, hdr ? 0 : SUB, (size_t)n);
    if (hdr) {
        int w = (int)strlen(XF_NAME) + 1;
        memcpy(x->buf + 3, XF_NAME, (size_t)w);
        for (const char *d = "2500 0 100644 0 1 2500"; *d; d++) x->buf[3 + w++] = (uint8_t)*d;
    } else {
        for (int i = (blk - 1) * 1024; i < XF_SIZE && i < blk * 1024; i++) x->buf[3 + i - (blk - 1) * 1024] = kestrel_xfer_byte(x->variant, i);
    }
    unsigned c = crc16(x->buf + 3, n);
    x->buf[3 + n] = (uint8_t)(c >> 8), x->buf[4 + n] = (uint8_t)c;
    x->len = 5 + n;
    emit(ctx, x->buf, x->len);
}

void kestrel_xfer_start(struct xfer *x, int kind)
{
    memset(x, 0, sizeof *x);
    x->kind = kind, x->st = START, x->blk = 1, x->last = (XF_SIZE + 1023) / 1024;
    x->variant = kind == XF_YMODEM2;
}
int kestrel_xfer_active(const struct xfer *x) { return x->kind && x->st != DONE; }

static int ymodem(const struct xfer *x) { return x->kind == XF_YMODEM || x->kind == XF_YMODEM2; }

static void next_block(struct xfer *x, emit_fn emit, void *ctx)
{
    static const uint8_t eot = EOT, cancel[5] = { CAN, CAN, CAN, CAN, CAN };
    if (x->kind == XF_CANCEL && x->blk == 2) { emit(ctx, cancel, 5); x->st = DONE; return; }
    if (x->blk == x->last) { emit(ctx, &eot, 1); x->st = EOT_ACK; return; }
    put_block(x, ++x->blk, 0, emit, ctx);
}

static void end_block(struct xfer *x, emit_fn emit, void *ctx) /* YMODEM's empty header: the batch is over */
{
    memset(x->buf, 0, sizeof x->buf);
    x->buf[0] = SOH, x->buf[2] = 255;
    unsigned c = crc16(x->buf + 3, 128);
    x->buf[131] = (uint8_t)(c >> 8), x->buf[132] = (uint8_t)c;
    emit(ctx, x->buf, 133);
}

static void xfer_step(struct xfer *x, uint8_t b, emit_fn emit, void *ctx)
{
    static const uint8_t eot = EOT;
    if (b == NAK && x->st == DATA_ACK) { emit(ctx, x->buf, x->len); return; }       /* resend */
    if (b == NAK && x->st == EOT_ACK) { emit(ctx, &eot, 1); return; }
    switch (x->st) {
    case START:
        if (b != 'C') break;
        if (ymodem(x)) { put_block(x, 0, 1, emit, ctx); x->st = HDR_ACK; }
        else { put_block(x, 1, 0, emit, ctx); x->st = DATA_ACK; }
        break;
    case HDR_ACK: if (b == ACK) x->st = DATA_C; break;
    case DATA_C: if (b == 'C') { put_block(x, 1, 0, emit, ctx); x->st = DATA_ACK; } break;
    case DATA_ACK: if (b == ACK) next_block(x, emit, ctx); break;
    case EOT_ACK: if (b == ACK) x->st = ymodem(x) ? END_C : DONE; break;
    case END_C: if (b == 'C') { end_block(x, emit, ctx); x->st = END_ACK; } break;
    case END_ACK: if (b == ACK) x->st = DONE; break;
    }
}

int kestrel_xfer_in(struct xfer *x, uint8_t b, emit_fn emit, void *ctx)
{
    x->cans = b == CAN ? x->cans + 1 : 0;
    if (x->cans >= 2) x->st = DONE;                      /* the receiver gave up: CAN CAN */
    else xfer_step(x, b, emit, ctx);
    if (kestrel_xfer_active(x)) return 0;
    char m[32];
    snprintf(m, sizeof m, "fakebbs: xfer %c done", x->kind);
    kestrel_log(m);
    return 1;
}

int kestrel_xfer_line(struct xfer *x, int c, emit_fn emit, void *ctx)
{
    static const char say[] = "\r\n\x1b[1;32mSending " XF_NAME ", start your download now.\x1b[0m\r\n";
    int k = c & ~32;
    if (k != XF_XMODEM && k != XF_YMODEM && k != XF_YMODEM2 && k != XF_CANCEL) return 0;
    emit(ctx, (const uint8_t *)say, (int)sizeof say - 1);
    kestrel_xfer_start(x, k);
    return 1;
}
