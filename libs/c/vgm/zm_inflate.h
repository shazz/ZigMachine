/* gzip (RFC 1952) / DEFLATE (RFC 1951) decoding for .vgz files, written from the two RFCs. Our own
 * code, MIT. Integers, no divide, ~1.4 KB of tables on the stack. */
#ifndef ZM_INFLATE_H
#define ZM_INFLATE_H

#include <stdint.h>

/* Inflate the raw DEFLATE stream src[0..slen) into dst[0..dcap). The output may sit BEFORE the input in
 * the same buffer: it is refused (0 answered) the moment it would reach the byte being read. The bytes
 * written, or 0 on a corrupt stream or one that does not fit. */
uint32_t zm_inflate(uint8_t *dst, uint32_t dcap, const uint8_t *src, uint32_t slen);

/* The gzip file at buf[0..len) inflated over itself, `cap` bytes of room at buf: the compressed bytes move
 * to the end of the room first. The inflated length (its ISIZE trailer checked), or 0. */
uint32_t zm_gunzip_in_place(uint8_t *buf, uint32_t len, uint32_t cap);

#endif
