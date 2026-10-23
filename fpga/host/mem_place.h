/* A wasm module's memory placed at a fixed offset in a 4 KiB page, not wherever the heap starts.
 *
 * ZIGGY's and BARD's D$ are 4 KiB and direct-mapped, so where a module's memory starts mod 4 KiB
 * decides which of its hot lines share a set with the C side's hot lines (the env/instance struct
 * read on every wasm access, the stack top). calloc put it wherever the heap began, so any change
 * of the firmware's statics moved it: 72 bytes of new statics cost rno_natrium 60 -> 54 fps, and a
 * 544-byte bigger demo-audio.wasm rodata doubled BARD's load (dbug's music 2.2 s late, rick_dangerous
 * 8 -> 16 %), 2026-10-23, prototypes/bard_icache_re. The offsets (cycles/bsys.c ZIGGY_MEM_SET,
 * host/audio.c BARD_MEM_SET) were measured on the board; re-measure one when that module's data
 * layout changes a lot. initial == maximum pages: the memory never grows, so it never moves. */
#ifndef ZM_MEM_PLACE_H
#define ZM_MEM_PLACE_H

#include <stdint.h>
#include <stdlib.h>

#include "wasm-rt.h"

static inline void zm_mem_place(wasm_rt_memory_t* m, uint64_t pages, uintptr_t set) {
    uint64_t bytes = pages * WASM_DEFAULT_PAGE_SIZE;
    uintptr_t raw = (uintptr_t)calloc(1, (size_t)bytes + 8192u);
    if (!raw) wasm_rt_trap(WASM_RT_TRAP_OOB);
    m->data = (uint8_t*)(((raw + 4095u) & ~(uintptr_t)4095u) + (set & 4095u));
    m->data_end = m->data + bytes;
    m->page_size = WASM_DEFAULT_PAGE_SIZE;
    m->pages = m->max_pages = pages;
    m->size = bytes;
    m->is64 = false;
}

#endif
