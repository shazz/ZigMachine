/* The recorder half of vdump (vdump.h). Writes, per dumped frame:
 *   f<N>.rec   the state records (kind uint8_t, pass uint8_t, raster line uint16_t, n uint16_t,
 *              n x (word uint16_t, value uint32_t)), little-endian, ending at EOF
 *   f<N>.pfb   the PFB after hwClear, then after each enabled plane, in order
 *   f<N>.mem   region offset 0 .. end of memory, as cart.frame() left it
 *   f<N>.meta  "planes <mask>\nvram_changed <0|1>\n" */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vdump.h"

static FILE* g_rec;
static FILE* g_pfb;
static char g_base[512];
static uint32_t g_prev[VD_STATE_WORDS];
static uint32_t g_pass;
static int g_phys; /* this plane's HBL counts PHYSICAL lines (video.zig) */
static uint8_t* g_mem_copy;
static size_t g_mem_len;

uint32_t vd_state_off(uint32_t i) {
    if (i < VD_REG_WORDS) return i * 4;
    if (i < VD_REG_WORDS + VD_PAL_WORDS) return ZM_OFF_PAL + (i - VD_REG_WORDS) * 4;
    return ZM_OFF_BEAM_TABLE + (i - VD_REG_WORDS - VD_PAL_WORDS) * 4;
}

static uint8_t* region(wasm_rt_memory_t* m) { return m->data + ZM_HW_VIDEO_BASE; }

static uint32_t rd(wasm_rt_memory_t* m, uint32_t off, int bytes) {
    uint32_t v = 0;
    memcpy(&v, region(m) + off, (size_t)bytes);
    return v;
}

static void put(FILE* f, uint32_t v, int bytes) { fwrite(&v, (size_t)bytes, 1, f); }

static void record(wasm_rt_memory_t* m, int kind, uint32_t line) {
    uint32_t now[VD_STATE_WORDS];
    uint16_t n = 0;
    for (uint32_t i = 0; i < VD_STATE_WORDS; i++) {
        now[i] = rd(m, vd_state_off(i), 4);
        n += now[i] != g_prev[i];
    }
    put(g_rec, (uint32_t)kind, 1);
    put(g_rec, g_pass, 1);
    put(g_rec, line, 2);
    put(g_rec, n, 2);
    for (uint32_t i = 0; i < VD_STATE_WORDS; i++) {
        if (now[i] == g_prev[i]) continue;
        put(g_rec, i, 2);
        put(g_rec, now[i], 4);
        g_prev[i] = now[i];
    }
}

static FILE* open_part(const char* ext) {
    char path[600];
    snprintf(path, sizeof path, "%s.%s", g_base, ext);
    FILE* f = fopen(path, "wb");
    if (!f) perror(path);
    return f;
}

int vd_begin(wasm_rt_memory_t* m, const char* dir, long frame) {
    (void)m;
    snprintf(g_base, sizeof g_base, "%s/f%ld", dir, frame);
    memset(g_prev, 0, sizeof g_prev); /* the first record carries the whole state */
    g_rec = open_part("rec");
    g_pfb = open_part("pfb");
    return g_rec && g_pfb ? 0 : -1;
}

/* Which line numbering this pass's HBL uses, mirroring video.zig renderPlane:
 * fullscreen, overscan and full-raster medium count physical lines 0..279. */
static int phys_lines(wasm_rt_memory_t* m, uint32_t plane) {
    uint32_t mode = rd(m, ZM_REG_FB_MODE + plane, 1);
    uint32_t stride = rd(m, ZM_REG_FB_STRIDE + plane * 2, 2);
    if (mode == ZM_FB_MODE_FULLSCREEN || mode == ZM_FB_MODE_OVERSCAN) return 1;
    if (mode == ZM_FB_MODE_MEDIUM) return stride >= ZM_RASTER_WIDTH;
    if (mode == ZM_FB_MODE_SCROLL) return 0;
    return stride == ZM_STRIDE_FULLSCREEN;
}

void vd_pass_start(wasm_rt_memory_t* m, uint32_t pass) {
    if (!g_rec) return;
    g_pass = pass;
    g_phys = pass == 0 || phys_lines(m, pass - 1);
    record(m, VD_PASS_START, 0);
}

void vd_pass_end(wasm_rt_memory_t* m) {
    if (g_rec) record(m, VD_PASS_END, 0);
}

void vd_hbl(wasm_rt_memory_t* m, int kind, uint32_t line) {
    if (g_rec) record(m, kind, g_phys ? line : line + ZM_RASTER_BORDER_Y);
}

void vd_dump_pfb(wasm_rt_memory_t* m) {
    if (g_pfb) fwrite(region(m) + ZM_OFF_PFB, 1, ZM_PFB_BYTES, g_pfb);
}

void vd_dump_mem(wasm_rt_memory_t* m) {
    g_mem_len = m->size - ZM_HW_VIDEO_BASE;
    free(g_mem_copy);
    g_mem_copy = malloc(g_mem_len);
    memcpy(g_mem_copy, region(m), g_mem_len);
    FILE* f = open_part("mem");
    if (!f) return;
    fwrite(g_mem_copy, 1, g_mem_len, f);
    fclose(f);
}

/* Did the render passes write memory the fetcher reads? (HBL handlers may;
 * the replay serves the pre-render image, so such a frame cannot match.) The
 * PFB and the recorded state are excluded: they are expected to change. */
static int vram_changed(wasm_rt_memory_t* m) {
    const uint8_t* now = region(m);
    for (size_t i = 0; i < g_mem_len; i++) {
        if (now[i] == g_mem_copy[i]) continue;
        if (i < ZM_OFF_VRAM) continue; /* registers and palettes */
        if (i >= ZM_OFF_PFB && i < ZM_OFF_BEAM_TABLE + ZM_BEAM_TABLE_BYTES) continue;
        return 1;
    }
    return 0;
}

void vd_end(wasm_rt_memory_t* m, uint32_t plane_mask) {
    FILE* meta = open_part("meta");
    if (meta) {
        fprintf(meta, "planes %u\nvram_changed %d\n", (unsigned)plane_mask, vram_changed(m));
        fclose(meta);
    }
    fclose(g_rec);
    fclose(g_pfb);
    g_rec = g_pfb = NULL;
}
