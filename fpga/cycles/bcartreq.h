/* The request block ZIGGY writes for ZWINDOW when the cart asks for a cart swap
 * (glass/src/map_cart.zig, read by glass/src/app_request.zig): the name words first, the
 * magic last, so a block whose magic and check hold is whole. Header-only so
 * tests/tb/cartreq_test.c writes it into a plain buffer. */
#ifndef ZM_BCARTREQ_H
#define ZM_BCARTREQ_H

#include <stdint.h>
#include <string.h>

#include "glass_cart.h"

static inline void bcartreq_write(volatile uint32_t* w, uint32_t req, const uint8_t* name, uint32_t len) {
    uint8_t bytes[CART_REQ_NAME_MAX] = {0};
    if (len > CART_REQ_NAME_MAX) len = CART_REQ_NAME_MAX;
    if (len) memcpy(bytes, name, len);
    for (uint32_t i = 0; i < CART_REQ_NAME_MAX / 4; i++)
        w[CART_REQ_HEAD_WORDS + i] = bytes[4 * i] | bytes[4 * i + 1] << 8 | bytes[4 * i + 2] << 16 |
                                     (uint32_t)bytes[4 * i + 3] << 24;
    w[1] = req;
    w[2] = len;
    w[3] = ~(CART_REQ_MAGIC ^ req ^ len);
    w[0] = CART_REQ_MAGIC;
}

#endif
