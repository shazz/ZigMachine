/* Force-included into every pt2 source (-include): the KESTREL port's hooks. */
#ifndef KESTREL_PORT_H
#define KESTREL_PORT_H
#include <stdint.h>
/* A screen bitmap decoded on demand into the one lazy slot (the previous one is freed). */
uint32_t *kestrel_bmp(uint32_t **slot, const uint8_t *packed, uint32_t len);
#define KBMP(n) kestrel_bmp(&n##BMP, n##PackedBMP, sizeof (n##PackedBMP))
#endif
