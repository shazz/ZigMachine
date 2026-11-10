/* kestrel_keys.c: the cart's key exports as a ring of ciolib key bytes. */
#ifndef KESTREL_KEYS_H
#define KESTREL_KEYS_H
#include <stdint.h>
int kestrel_keys_waiting(void);       /* 1: a byte is waiting */
int kestrel_keys_get(void);           /* the next byte, -1 when none */
void kestrel_keys_push(uint16_t code); /* a ciolib code (byte, or 0x00 + scan code) */
#endif
