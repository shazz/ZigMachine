/* On-demand screen bitmaps: pt2 unpacks every GUI bitmap at boot to 32-bit ARGB (~1.2 MB for 4-colour
 * art), more than the 2 MiB cart window leaves. The 12 big overlays are each blitted from one place,
 * so they share one slot: decoding one frees the previous (a few ms when a screen opens). */
#include <stdlib.h>
#include <stdint.h>
uint32_t *unpackBMP(const uint8_t *src, uint32_t packedLen);
void kestrel_log(const char *m);

static uint32_t **live;

uint32_t *kestrel_bmp(uint32_t **slot, const uint8_t *packed, uint32_t len)
{
    if (live && live != slot && *live) { free(*live); *live = NULL; }
    if (!*slot) {
        *slot = unpackBMP(packed, len);
        if (!*slot) kestrel_log("pt2: out of memory decoding a screen bitmap");
    }
    live = slot;
    return *slot;
}
