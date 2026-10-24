/* A disk's executable boot sector, run as the browser runs it: host/bootsec.h. */
#include "bootsec.h"

#include <string.h>

static uint64_t imp_video_base(void* ctx, const uint64_t* args) {
    (void)args;
    return ((const bootsec_t*)ctx)->video_base;
}

static uint64_t imp_beep(void* ctx, const uint64_t* args) {
    (void)args;
    const bootsec_t* b = ctx;
    if (b->beep) b->beep();
    return 0;
}

static const wint_import IMPORTS[] = {{"hwVideoBase", imp_video_base}, {"beep", imp_beep}};

int bootsec_executable(const uint8_t* disk, uint32_t size) {
    static const uint8_t wasm[4] = {0, 'a', 's', 'm'};
    if (!disk || size < 0x600 || memcmp(disk, wasm, 4) != 0 || memcmp(disk + 0x400, "ZMDISK", 6) != 0) return 0;
    uint16_t sum = 0;
    for (uint32_t i = 0; i < BOOTSEC_BYTES; i += 2) sum = (uint16_t)(sum + (disk[i] << 8 | disk[i + 1]));
    return sum == 0x1234;
}

const char* bootsec_status(wint_status st) {
    static const char* const names[] = {"ok", "format", "unsupported", "link", "unreachable",
                                        "oob", "div", "stack", "fuel", "type"};
    return (unsigned)st < sizeof names / sizeof names[0] ? names[st] : "?";
}

/* The exports the loop calls; pollCartRequest is optional (the browser checks for it). */
static wint_status exports(bootsec_t* b) {
    b->f_boot = wint_export_func(&b->w, "boot");
    b->f_frame = wint_export_func(&b->w, "frame");
    b->f_plane = wint_export_func(&b->w, "isPlaneEnabled");
    b->f_poll = wint_export_func(&b->w, "pollCartRequest");
    if (b->f_boot < 0 || b->f_frame < 0 || b->f_plane < 0) {
        b->w.why = "no boot/frame/isPlaneEnabled export";
        return WINT_E_LINK;
    }
    return WINT_OK;
}

wint_status bootsec_start(bootsec_t* b, const uint8_t* disk, uint8_t* mem, uint32_t mem_len, uint32_t video_base,
                          void (*beep)(void)) {
    b->video_base = video_base, b->beep = beep, b->frames = 0;
    b->st = wint_load(&b->w, disk, BOOTSEC_BYTES, mem, mem_len, IMPORTS, 2, b);
    if (!b->st) b->st = exports(b);
    uint64_t r;
    if (!b->st) b->st = wint_call(&b->w, b->f_boot, NULL, 0, &r, BOOTSEC_FUEL_BOOT);
    return b->st;
}

int bootsec_frame(bootsec_t* b, float dt) {
    uint64_t r = 0, arg;
    uint32_t bits;
    memcpy(&bits, &dt, 4); /* an f32 parameter is its bits */
    arg = bits;
    if (b->st || b->frames >= BOOTSEC_MAX_FRAMES) return -1;
    b->frames++;
    b->st = wint_call(&b->w, b->f_frame, &arg, 1, &r, BOOTSEC_FUEL_FRAME);
    if (!b->st && b->f_poll >= 0) b->st = wint_call(&b->w, b->f_poll, NULL, 0, &r, BOOTSEC_FUEL_FRAME);
    if (b->st) return -1;
    return (uint32_t)r == BOOTSEC_CHAINLOAD && b->f_poll >= 0;
}

int bootsec_plane_on(bootsec_t* b, uint32_t p) {
    uint64_t r = 0, arg = p;
    if (b->st) return 0;
    b->st = wint_call(&b->w, b->f_plane, &arg, 1, &r, BOOTSEC_FUEL_FRAME);
    return !b->st && (uint32_t)r != 0;
}
