# `machine/` — the sealed ZigMachine hardware

The fantasy console itself. **Maintained by the ZigMachine authors only** — apps
and ROMs treat this as fixed silicon. It compiles to the two sealed wasm
binaries (`machine-video.wasm`, `machine-audio.wasm`) that everything else links
against through a memory-mapped ABI.

## Layout
- `machine_video.zig` / `machine_audio.zig` — the two sealed binary entry points.
- `video.zig`, `blitter.zig`, `audio/` — the implementation (border/raster/plane
  pipeline, 2D blitter, YM/sample audio). **Tread carefully — changing register
  offsets is an ABI break** ([[zigmachine-abi-rebuild-gotcha]]).
- `sdk/` — the **published ABI headers** the rest of the repo receives:
  - `memmap.zig` — the single source of truth for the memory map (offsets, registers).
  - `hardware.zig` — video ABI (extern `hw*` fns + geometry constants).
  - `audio.zig` — audio ABI.

Anyone linking against `sdk/` (a lib, a ROM, an app — in any language) gets the
machine; nobody gets `machine/` source. That's the seal.

## Build & run
```bash
zig build -Dwasm -Drelease=true      # -> docs/{machine-video,demo,machine-audio,demo-audio}.wasm
cd docs && python3 -m http.server 3333   # open http://localhost:3333/sealed.html
```
Changing an ABI offset → **clean-rebuild both** `machine-*.wasm` and the app/ROM
that link it, then hard-reload the browser.

> **Coming:** `machine/boot.zig` — the power-on/POST screen, rewritten to draw via
> `sdk/` only so the machine renders its own boot (currently still app-linked).
