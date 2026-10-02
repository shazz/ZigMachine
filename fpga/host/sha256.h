/* SHA-256 (FIPS 180-4), streaming. The host fingerprints frames with the same
 * hash apps/scene_hash.mjs takes from node:crypto, so the JSON compares as text.
 * Plain C11 with no platform calls, so it builds unchanged for rv32. */
#ifndef HOST_SHA256_H
#define HOST_SHA256_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t h[8];
    uint64_t len;      /* bytes hashed so far */
    uint8_t buf[64];
    size_t fill;
} sha256_ctx;

void sha256_init(sha256_ctx* c);
void sha256_update(sha256_ctx* c, const void* data, size_t n);
/* Writes the digest as 64 lowercase hex chars plus a NUL into hex[65]. */
void sha256_hex(sha256_ctx* c, char hex[65]);

#endif
