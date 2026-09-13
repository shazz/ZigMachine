# `libs/zig/` — ZigOS (the open Zig library)

The coder-facing Zig library, built on the HW ABI (`@import("hardware")`). Apps
reach it with `@import("zigos")`; the audio players with `@import("players")`.

## What's inside
- `zigos.zig` — umbrella: `ZigOS`, `LogicalFB`, palette/`printText`, `Blitter`,
  `obj` loader, `za` (vector/matrix math), and re-exported effects.
- `effects/` — reusable effects: scrolltext, parallax, tilemap (horizontal bands,
  and 2D `Grid` maps with `drawGrid`, a collision `cellAt`, melonJS-style camera
  `followAxis` and `RatioScroll` parallax — pure parts in `tilegrid.zig`), bobs,
  starfields, fades, dots3d, mandelbrot, boot effect, …
- `players/` — MOD / YM / sample players (link `@import("players")` +
  `@import("audio_hw")`).
- `utils/` — loaders, debug `Console`, obj loader, zalgebra.
- `blitter.zig` — ergonomic wrapper over the sealed blitter registers.
- `assets/` — data the library itself embeds.

GEM used to live here; it moved to `rom/gem/` to keep the layering clean
(`machine` → `libs` → `rom` → `apps`).

## Build
Compiled as a named module by the top-level build — no separate artifact:
```bash
zig build -Dwasm -Drelease=true      # -> docs/demo.wasm (+ machine, audio)
cd docs && python3 -m http.server 3333
```
See `docs/ZIGOS_API.md` for the full API.
