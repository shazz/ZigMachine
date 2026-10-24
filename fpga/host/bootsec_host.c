/* The native host's --bootsec X.zmd (host/main.c): the disk's executable boot sector run as
 * the board firmware runs it (host/bootsec.h, cycles/bbootsec.c), through the same wint
 * interpreter, over the wasm2c'd machine, and hashed as apps/scene_hash.mjs hashes it when
 * given the same .zmd (its 1 KB sector instantiated by the browser's engine): the picture
 * check of the board's boot screen against the browser's. */
#include "bootsec_host.h"

#include <stdio.h>
#include <stdlib.h>

#include "bootsec.h"
#include "sha256.h"

static bootsec_t g_b;
static uint8_t* g_disk;

int host_bootsec_start(struct w2c_env* e, const char* path) {
    FILE* f = fopen(path, "rb");
    long n = -1;
    if (f && fseek(f, 0, SEEK_END) == 0) n = ftell(f), rewind(f);
    g_disk = n > 0 ? malloc((size_t)n) : NULL;
    if (!f || !g_disk || fread(g_disk, 1, (size_t)n, f) != (size_t)n) {
        fprintf(stderr, "host: cannot read %s\n", path);
        return -1;
    }
    fclose(f);
    if (!bootsec_executable(g_disk, (uint32_t)n)) {
        fprintf(stderr, "host: %s has no executable boot sector\n", path);
        return -1;
    }
    w2c_machine_hwInit(&e->machine); /* the browser: instantiate the sector, hwInit, boot() */
    wint_status st = bootsec_start(&g_b, g_disk, e->memory.data, (uint32_t)e->memory.size,
                                   w2c_machine_hwVideoBase(&e->machine), NULL);
    fprintf(stderr, "host: boot sector %s, boot() %lu instructions\n", bootsec_status(st), (unsigned long)g_b.w.steps);
    return st ? -1 : 0;
}

void host_bootsec_frame(struct w2c_env* e, sha256_ctx* h, uint32_t planes, uint32_t size) {
    w2c_machine_hwClear(&e->machine);
    if (bootsec_frame(&g_b, 16.6f) < 0 && g_b.st) { /* the frame cap is the board's, not scene_hash's */
        fprintf(stderr, "host: boot sector: %s\n", bootsec_status(g_b.st));
        exit(1);
    }
    for (uint32_t p = 0; p < planes; p++) {
        if (!bootsec_plane_on(&g_b, p)) {
            char off[16];
            if (h) sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
            continue;
        }
        w2c_machine_hwRenderPlane(&e->machine, p);
        if (h) sha256_update(h, e->memory.data + w2c_machine_hwPhysicalPtr(&e->machine), size);
    }
}
