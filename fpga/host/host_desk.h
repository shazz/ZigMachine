/* The desk mode's frame hash (HW 1.17.0, docs/HW_API.md "Desk mode"), as apps/scene_hash.mjs
 * takes it: "desk", the bars' colour (hwDeskBars, 4 bytes little-endian: R, G, B, 255), then
 * hwRenderDesk(0)'s and hwRenderDesk(1)'s 640x240 RGBA halves out of the PFB. One definition
 * for the native host (main.c) and the board's firmware (cycles/bdesk.c). */
#ifndef HOST_DESK_H
#define HOST_DESK_H
#include "host.h"
#include "sha256.h"

#define HOST_DESK_HALF ((size_t)640 * 240 * 4)

static inline void host_desk_hash(struct w2c_env* e, sha256_ctx* h) {
    const uint8_t* pfb = e->memory.data + w2c_machine_hwPhysicalPtr(&e->machine);
    uint32_t bars = w2c_machine_hwDeskBars(&e->machine);
    uint8_t le[4] = {(uint8_t)bars, (uint8_t)(bars >> 8), (uint8_t)(bars >> 16), (uint8_t)(bars >> 24)};
    sha256_update(h, "desk", 4);
    sha256_update(h, le, 4);
    for (uint32_t half = 0; half < 2; half++) {
        w2c_machine_hwRenderDesk(&e->machine, half);
        sha256_update(h, pfb, HOST_DESK_HALF);
    }
}
#endif
