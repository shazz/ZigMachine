# Session Handoff

**Date:** 2026-08-22 (evening)
**Branch:** `feat/sealed-hardware` (off `main`; `main` still 29 ahead of origin, unpushed)
**Author:** matt-grain (+ Anima)

## What Was Done — the hardware is SEALED

Turned the sealed-hardware **spec** into a **working, in-browser-proven** reality.
`music_debug` runs **unchanged** at ~60fps against a sealed machine binary, with
MOD/YM/sample audio + the 4-channel oscilloscope. Verified at `docs/sealed.html`.

### Commits on this branch (newest first)
1. `Reorg into hw/ zigos/ apps/ legacy/` — the physical split (below).
2. `docs: add HW_API and ZIGOS_API` — the two reference docs.
3. `Seal the hardware: memory-mapped video + audio ABI` — the feature.
   *(this-pass cleanup — seal guard + effect fixes — committed on top)*

### The architecture
- **Two sealed binaries**, each sharing ONE `WebAssembly.Memory` with the open
  coder module on its thread:
  - main thread: `machine-video.wasm` (sealed render pipeline) + `demo.wasm` (ZigOS+scene)
  - worklet thread: `machine-audio.wasm` (Paula+YM2149) + `demo-audio.wasm` (players)
- **Memory-mapped ABI**, single source of truth: `hw/sdk/memmap.zig` (video),
  `hw/sdk/audio.zig` (audio). Published headers: `hw/sdk/hardware.zig` + `audio.zig`.
- **Callback inversion** (only ints cross the seal): video `env.hblDispatch`,
  audio `machinePaula*`/`machineYmWrite`/`machineMix*`.
- **Reserved address trick**: the video region lives at a fixed `0x200000` above
  both modules' data (demo `--global-base=0x100000`), so two wasm modules share
  one memory with zero collision. Same idea for audio (song RAM at `0x200000`).

### Repo layout (the reorg)
```
hw/     SEALED — video.zig + pipeline, machine_{video,audio}.zig, audio/{engine,ym}.zig, sdk/
zigos/  OPEN   — zigos.zig, effects/, players/{mod,ym_player}, utils/ (+math), assets/fonts/
apps/   OPEN   — scenes/, demo_main.zig, demo_audio_main.zig, floppy.zig, assets/
legacy/ retired pre-seal monolith (bootloader.zig, audio_main.zig, sound/)
docs/   web host: sealed.html + sealed-loader.js + audio-worklet-sealed.js + the 4 .wasm
```
Cross-folder deps via Zig **named modules** in `build.zig` (`zigos`, `players`,
`hardware`, `audio_hw`). Seal enforced structurally + by `tools/check_seal.sh`.

## Current State
- [x] `zig build -Drelease=true -Dwasm` green → `docs/{machine-video,demo,machine-audio,demo-audio}.wasm`
- [x] `music_debug` runs unchanged at ~60fps with audio + scope (`docs/sealed.html`)
- [x] `tools/check_seal.sh` passes
- [x] Legacy `index.html`/`loader.js` + committed `bootloader.wasm`/`audio.wasm` untouched (A/B)

## Docs
- `docs/HW_API.md` — the sealed hardware ABI (memory map, registers, entry points, audio ops).
- `docs/ZIGOS_API.md` — the open library scenes/effects are written against.
- `docs/HARDWARE_SPEC.md` §12 — full built-vs-deferred status + design refinements.

## Blockers & Open Questions
- [ ] **Give the audio a listen.** Verified by scope + clean console (chip DSP
      reused verbatim, so it *should* be identical) but NOT hear-verified.
- [ ] Push? `main` is 29 ahead of origin; this work is on `feat/sealed-hardware`
      (not merged to `main`, not pushed).

## Next Session (remaining deferred, priority order)
1. **Migrate the other ~22 scenes** to `@import("zigos")` + build each as a
   channel against the sealed loader (music_debug is the worked example).
2. **Retire `legacy/`** once `index.html` is moved to the sealed modules.
3. **Overscan**: the PFB border-poke can't be trivially replaced — it needs a new
   sanctioned machine feature (physical-res overlay / border sprite layer). See
   HARDWARE_SPEC §12 "Findings".

**Build:** `export PATH="$HOME/.local/zig/0.16.0:$PATH" && zig build -Drelease=true -Dwasm`
then `cd docs && python3 -m http.server 3333` → `/sealed.html` (hard-reload after rebuilds).

---
*Generated for the next session — the seal is done; the tail is scene migration.*
