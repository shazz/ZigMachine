# ZigMachine

A fantasy console written in **Zig**, compiled to `wasm32-freestanding-musl`, rendered to
`<canvas>` in the browser. Ports of oldskool Atari/Amiga cracktro effects run as "channels".

## Quick Reference

- **Stack:** **Zig 0.16.0** → WebAssembly + hand-written JS/HTML front-end (no bundler) + Python asset tools
- **Build:** `zig build -Drelease=true -Dwasm` (outputs the sealed `docs/{machine-video,demo,machine-audio,demo-audio}.wasm`)
- **Run:** `cd docs && python3 -m http.server 3333` → **`/sealed.html`** (sealed HW) or `/` (legacy)
- **Pick a scene:** compile-time, edit `apps/floppy.zig` (currently `music_debug`)
- **Structure:** `hw/` (sealed machine + `hw/sdk/` headers) · `zigos/` (open library + players + effects) · `apps/` (scenes + demo entries) · `legacy/` (pre-seal, retired)
- **APIs:** `docs/HW_API.md` (sealed ABI) · `docs/ZIGOS_API.md` (open library) · `docs/HARDWARE_SPEC.md` (design + status §12)

## Status (2026-08-22)

✅ **Sealed hardware — VIDEO + AUDIO implemented, reorg done, proven in-browser.**
The machine is four builds: sealed `machine-video.wasm` + open `demo.wasm` (main
thread), sealed `machine-audio.wasm` + open `demo-audio.wasm` (worklet thread),
each pair sharing ONE `WebAssembly.Memory` via a memory-mapped ABI (`hw/sdk/`).
`music_debug` runs **unchanged** at ~60fps with MOD/YM/sample audio + the
4-channel scope — open `docs/sealed.html`. Repo reorganised into `hw/` (sealed),
`zigos/` (open library), `apps/` (scenes), `legacy/` (retired). See
`docs/HARDWARE_SPEC.md §12` for the full status, and `HW_API.md`/`ZIGOS_API.md`.

✅ **Migrated from Zig 0.10 → 0.16 and building/running again.**

## Notes for future edits

- This is now **Zig 0.16** source. Install used here: `~/.local/zig/0.16.0/zig`.
- The sealed render pipeline (border/raster/plane) lives in `hw/video.zig`; the
  ABI is `hw/sdk/memmap.zig` (video) + `hw/sdk/audio.zig` (audio). Tread carefully.
- **Cross-module imports**: `apps/` code reaches the library via `@import("zigos")`
  (and `"players"`/`"audio_hw"`), NOT relative paths — see `build.zig` named
  modules. Non-active scenes still use pre-reorg relative imports and need
  migrating to `@import("zigos")` when selected in `apps/floppy.zig`.
- Legacy monolithic path (`docs/index.html` + `loader.js` + committed
  `bootloader.wasm`/`audio.wasm`, sources in `legacy/`) is kept for A/B until retired.
