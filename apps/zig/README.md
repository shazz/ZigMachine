# `apps/zig/` — the ZigOS demo (Zig scenes)

The main cartridge: boot screen → effects menu → scenes. Compiles to
`docs/demo.wasm`, linked against `zigos`, `rom` (GEM), `players`, and the HW ABI.

## Layout
- `demo_main.zig` — `demo.wasm` entry (video/main thread): boot ROM screen, then
  the selected cart; exports `boot`/`frame`/`hblDispatch`/`isPlaneEnabled`/… .
- `demo_audio_main.zig` — `demo-audio.wasm` entry (worklet thread): ZigOS players.
- `floppy.zig` — **compile-time scene selector** (uncomment one `Demo`).
- `scenes/` — every scene (menu, Union intro + `union/`, cracktro ports, GEM
  desktop host, music debug, blitter/scroll/obj demos, …).
- `assets/` — data the scenes `@embedFile` (paths are relative: `../assets/…`).

## Pick a scene
Edit `floppy.zig` (currently `menu` — the runtime effects menu, which lists and
launches scenes at runtime). Active scenes use the named modules
(`@import("zigos")` / `"rom"` / `"players"`); some retired scenes still use
pre-reorg relative imports and need migrating when selected.

## Build & run
```bash
zig build -Dwasm -Drelease=true          # -> docs/demo.wasm
cd docs && python3 -m http.server 3333   # http://localhost:3333/sealed.html
```
Hard-reload after every rebuild. See `docs/ZIGOS_API.md` + `docs/HW_API.md`.
