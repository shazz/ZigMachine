/* DEFLATE and gzip decoding (zm_inflate.h), from RFC 1951 (block types, canonical Huffman codes, the
 * length / distance bases) and RFC 1952 (the member header and trailer). Our own code. */
#include "zm_inflate.h"

#include <string.h>

typedef struct {
    const uint8_t *src;
    uint32_t slen, at, bits, nbits;
    uint8_t *dst;
    uint32_t dcap, out, bad;
} inf;

typedef struct {
    uint16_t count[16], sym[320];
} huff;

static uint32_t need(inf *s, uint32_t n) {
    while (s->nbits < n) {
        if (s->at >= s->slen) return s->bad = 1, 0;
        s->bits |= (uint32_t)s->src[s->at++] << s->nbits;
        s->nbits += 8;
    }
    uint32_t v = s->bits & ((1u << n) - 1u);
    s->bits >>= n;
    s->nbits -= n;
    return v;
}

/* Canonical code from code lengths (RFC 1951 3.2.2): counts per length, symbols in code order. */
static void build(huff *h, const uint8_t *len, uint32_t n) {
    uint16_t offs[16];
    memset(h->count, 0, sizeof h->count);
    for (uint32_t i = 0; i < n; i++) h->count[len[i]]++;
    h->count[0] = 0;
    offs[1] = 0;
    for (uint32_t i = 1; i < 15; i++) offs[i + 1] = (uint16_t)(offs[i] + h->count[i]);
    for (uint32_t i = 0; i < n; i++)
        if (len[i]) h->sym[offs[len[i]]++] = (uint16_t)i;
}

/* One symbol, bit by bit (codes are packed MSB first). */
static uint32_t decode(inf *s, const huff *h) {
    int32_t code = 0, first = 0, index = 0;
    for (uint32_t l = 1; l < 16; l++) {
        code |= (int32_t)need(s, 1);
        int32_t c = h->count[l];
        if (code - c < first) return h->sym[index + (code - first)];
        index += c;
        first = (first + c) << 1;
        code <<= 1;
        if (s->bad) return 0;
    }
    return s->bad = 1, 0;
}

static const uint16_t LBASE[29] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                   35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
static const uint8_t LEXT[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
static const uint16_t DBASE[30] = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                   257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
static const uint8_t DEXT[30] = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};

/* The output may not reach the input: in place, the next byte read is at src + at. */
static int put_ok(const inf *s, uint32_t n) {
    if (s->out + n > s->dcap) return 0;
    return s->dst + s->out + n <= s->src + s->at || s->dst + s->out >= s->src + s->slen;
}

static void codes(inf *s, const huff *lit, const huff *dist) {
    for (;;) {
        uint32_t sym = decode(s, lit);
        if (s->bad || sym == 256) return;
        if (sym < 256) {
            if (!put_ok(s, 1)) return (void)(s->bad = 1);
            s->dst[s->out++] = (uint8_t)sym;
            continue;
        }
        sym -= 257;
        if (sym >= 29) return (void)(s->bad = 1);
        uint32_t len = LBASE[sym] + need(s, LEXT[sym]), d = decode(s, dist);
        if (d >= 30) return (void)(s->bad = 1);
        uint32_t back = DBASE[d] + need(s, DEXT[d]);
        if (s->bad || back > s->out || !put_ok(s, len)) return (void)(s->bad = 1);
        for (uint32_t i = 0; i < len; i++, s->out++) s->dst[s->out] = s->dst[s->out - back];
    }
}

static void stored(inf *s) {
    s->bits = s->nbits = 0; /* to a byte boundary */
    if (s->at + 4 > s->slen) return (void)(s->bad = 1);
    uint32_t n = s->src[s->at] | s->src[s->at + 1] << 8;
    s->at += 4;
    if (n > s->slen - s->at) return (void)(s->bad = 1);
    for (uint32_t i = 0; i < n; i++) {
        if (!put_ok(s, 1)) return (void)(s->bad = 1);
        s->dst[s->out++] = s->src[s->at++];
    }
}

static void fixed(inf *s) {
    uint8_t len[320];
    huff lit, dist;
    for (uint32_t i = 0; i < 288; i++) len[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8;
    build(&lit, len, 288);
    memset(len, 5, 30);
    build(&dist, len, 30);
    codes(s, &lit, &dist);
}

static void dynamic(inf *s) {
    static const uint8_t ORDER[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
    uint8_t len[320];
    huff lit, dist;
    uint32_t nlen = need(s, 5) + 257, ndist = need(s, 5) + 1, ncode = need(s, 4) + 4;
    if (nlen > 286 || ndist > 30) return (void)(s->bad = 1);
    memset(len, 0, 19);
    for (uint32_t i = 0; i < ncode; i++) len[ORDER[i]] = (uint8_t)need(s, 3);
    build(&lit, len, 19);
    for (uint32_t i = 0; i < nlen + ndist && !s->bad;) {
        uint32_t sym = decode(s, &lit), rep = 0, val = 0;
        if (sym < 16) { len[i++] = (uint8_t)sym; continue; }
        if (sym == 16) { if (!i) return (void)(s->bad = 1); val = len[i - 1], rep = 3 + need(s, 2); }
        else rep = sym == 17 ? 3 + need(s, 3) : 11 + need(s, 7);
        if (i + rep > nlen + ndist) return (void)(s->bad = 1);
        while (rep--) len[i++] = (uint8_t)val;
    }
    if (s->bad) return;
    build(&lit, len, nlen);
    build(&dist, len + nlen, ndist);
    codes(s, &lit, &dist);
}

uint32_t zm_inflate(uint8_t *dst, uint32_t dcap, const uint8_t *src, uint32_t slen) {
    inf s = {.src = src, .slen = slen, .dst = dst, .dcap = dcap};
    uint32_t last;
    do {
        last = need(&s, 1);
        uint32_t type = need(&s, 2);
        if (type == 0) stored(&s);
        else if (type == 1) fixed(&s);
        else if (type == 2) dynamic(&s);
        else s.bad = 1;
    } while (!last && !s.bad);
    return s.bad ? 0 : s.out;
}

uint32_t zm_gunzip_in_place(uint8_t *buf, uint32_t len, uint32_t cap) {
    if (len < 18 || len > cap || buf[0] != 0x1F || buf[1] != 0x8B || buf[2] != 8) return 0;
    uint32_t flg = buf[3], at = 10, size = buf[len - 4] | buf[len - 3] << 8 | buf[len - 2] << 16 | (uint32_t)buf[len - 1] << 24;
    if (flg & 4u) at += 2u + (buf[10] | buf[11] << 8);
    if (flg & 8u) while (at < len && buf[at++]) {}
    if (flg & 16u) while (at < len && buf[at++]) {}
    if (flg & 2u) at += 2;
    if (at + 8 > len || size == 0 || size > cap) return 0;
    uint32_t n = len - 8 - at;
    uint8_t *src = buf + cap - n;
    memmove(src, buf + at, n);
    return zm_inflate(buf, cap, src, n) == size ? size : 0;
}
