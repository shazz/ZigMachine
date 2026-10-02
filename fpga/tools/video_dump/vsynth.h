/* vsynth: synthetic frames for the RTL compositor's replay test, rendered by the
 * REAL machine-video (wasm2c'd), with no cart and no ROM. A scenario programs
 * the video registers, palettes and VRAM directly and plays the HBL handlers,
 * so it can reach what no shipping cart does today: FB_MODE_FULLSCREEN (ZigOS
 * no longer sets it), per-line HSCROLL, odd strides, unaligned screen bases,
 * BEAM lists that break the 68000's limits, mistimed flickers. The machine is
 * still the oracle: vsynth only decides what to ask it. */
#ifndef VSYNTH_H
#define VSYNTH_H

#include <stdint.h>

typedef struct {
    const char* name;
    int frames;          /* frames to run; every one is recorded */
    unsigned planes;     /* enabled-plane mask (the cart's isPlaneEnabled) */
    void (*setup)(void); /* after hwInit */
    void (*frame)(int f);                                  /* the cart's frame(), f = 1.. */
    void (*hbl)(uint32_t id, uint32_t plane, uint32_t line); /* every hblDispatch */
} vs_scenario;

extern const vs_scenario vs_scenarios[]; /* name == NULL ends it */

/* The video region, and little-endian accessors into it (region offsets). */
extern uint8_t* vs_region;
void vs_w8(uint32_t off, uint32_t v);
void vs_w16(uint32_t off, uint32_t v);
void vs_w32(uint32_t off, uint32_t v);
uint32_t vs_r16(uint32_t off);
uint32_t vs_rnd(void); /* xorshift32, fixed seed: every run asks the same */

/* Fill n bytes of VRAM at off with random palette indices; random opaque palette. */
void vs_fill(uint32_t off, uint32_t n);
void vs_palette(int plane);
/* Point plane p at (mode, stride, base) with its per-plane HBL (id p + 1) at hpos. */
void vs_plane(int p, int mode, int stride, uint32_t base, int hpos);

#endif
