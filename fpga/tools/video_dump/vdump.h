/* vdump: the native host (fpga/host/) plus a recorder that captures, for the
 * frames asked for, everything the RTL video compositor needs to replay them:
 * the memory its line fetcher reads, the register/palette/BEAM state each pass
 * consumed on each line, and the PFB the wasm machine produced. See README.md.
 *
 * Constants come from build/vdump/zm_memmap.h, generated from gen/memmap.py by
 * tools/video_dump.py, so no memmap offset is retyped here. */
#ifndef VDUMP_H
#define VDUMP_H

#include <stdint.h>

#include "wasm-rt.h"
#include "zm_memmap.h"

/* The state the compositor reads, as one array of little-endian words:
 * the video register block (0x00..0x7F), the 4 palettes, the BEAM table. */
#define VD_REG_WORDS 32
#define VD_PAL_WORDS (ZM_NB_PLANES * ZM_PAL_ENTRIES)
#define VD_BEAM_WORDS ZM_BEAM_MAX
#define VD_STATE_WORDS (VD_REG_WORDS + VD_PAL_WORDS + VD_BEAM_WORDS)

/* Record kinds, in the order the machine produces them. PRE/POST bracket one
 * hblDispatch; PASS_START/PASS_END bracket hwClear (pass 0) or hwRenderPlane
 * (pass p + 1). Each record holds only the words that changed since the one
 * before it, so replaying them in order rebuilds the machine's state. */
enum { VD_PRE = 1, VD_POST = 2, VD_PASS_START = 3, VD_PASS_END = 4 };

/* Region-relative byte offset of state word i. */
uint32_t vd_state_off(uint32_t i);

/* Open <dir>/f<frame>.{rec,pfb,mem,meta}; recording is on until vd_end. */
int vd_begin(wasm_rt_memory_t* m, const char* dir, long frame);
void vd_end(wasm_rt_memory_t* m, uint32_t plane_mask);

/* Pass boundaries, called by the frame loop. */
void vd_pass_start(wasm_rt_memory_t* m, uint32_t pass);
void vd_pass_end(wasm_rt_memory_t* m);

/* Save the PFB / the memory the fetcher reads (region offset 0 to the end). */
void vd_dump_pfb(wasm_rt_memory_t* m);
void vd_dump_mem(wasm_rt_memory_t* m);

/* Called around every hblDispatch while recording. */
void vd_hbl(wasm_rt_memory_t* m, int kind, uint32_t line);

#endif
