/* LEB128 readers for wint (wint.h). Each reads at *pc, never at or past `end`, and advances
 * *pc; it returns 0 on success, -1 on a truncated or over-long number. The load and the scan
 * use these checked forms, so the interpreter can trust every immediate it reads again. */
#ifndef ZM_WINT_LEB_H
#define ZM_WINT_LEB_H

#include <stdint.h>

static inline int wint_leb(const uint8_t* m, uint32_t end, uint32_t* pc, int bits, int sign, uint64_t* out) {
    uint64_t v = 0;
    int shift = 0;
    uint8_t b;
    do {
        if (*pc >= end || shift >= bits) return -1; /* ceil(bits / 7) bytes at most */
        b = m[(*pc)++];
        v |= (uint64_t)(b & 0x7F) << shift;
        shift += 7;
    } while (b & 0x80);
    if (sign && shift < 64 && (b & 0x40)) v |= ~(uint64_t)0 << shift;
    if (bits < 64) v &= sign ? ~(uint64_t)0 : (((uint64_t)1 << bits) - 1);
    *out = v;
    return 0;
}

static inline int wint_u32(const uint8_t* m, uint32_t end, uint32_t* pc, uint32_t* out) {
    uint64_t v;
    if (wint_leb(m, end, pc, 32, 0, &v)) return -1;
    *out = (uint32_t)v;
    return 0;
}

static inline int wint_byte(const uint8_t* m, uint32_t end, uint32_t* pc, uint8_t* out) {
    if (*pc >= end) return -1;
    *out = m[(*pc)++];
    return 0;
}

/* The interpreter's reads, of immediates the scan already checked. */
static inline uint32_t wint_ru32(const uint8_t* m, uint32_t* pc) {
    uint32_t v = 0;
    int shift = 0;
    uint8_t b;
    do {
        b = m[(*pc)++];
        v |= (uint32_t)(b & 0x7F) << shift;
        shift += 7;
    } while (b & 0x80);
    return v;
}

static inline uint64_t wint_rs64(const uint8_t* m, uint32_t* pc) {
    uint64_t v = 0;
    int shift = 0;
    uint8_t b;
    do {
        b = m[(*pc)++];
        v |= (uint64_t)(b & 0x7F) << shift;
        shift += 7;
    } while (b & 0x80);
    if (shift < 64 && (b & 0x40)) v |= ~(uint64_t)0 << shift;
    return v;
}

#endif
