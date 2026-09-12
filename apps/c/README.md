# `apps/c/` — hello world in C

`hello.c` — an animated plasma proving the sealed ABI is language-agnostic. Same
`machine-video.wasm` as the Zig demo, driven from C: two imports
(`env.memory` + `hwVideoBase()`), a handful of exports, 8-bit palette indices
written straight into the shared video region.

## The contract this app implements
- **Imports** (`env`): `memory`, `hwVideoBase()`, `consoleLogJS(ptr,len)`.
- **Exports**: `boot()`, `frame(f32)`, `isPlaneEnabled(i)->bool` (required), plus
  no-op `hblDispatch/skipBoot/setShadeMode/pointer/input`.
- **Draw**: palette-index bytes at `hwVideoBase()+OFF_VRAM`; RGBA palette at
  `+OFF_PAL` (**alpha 255 = opaque**). Offsets mirror `machine/sdk/memmap.zig`.
- **Link layout** (must match `build.zig`'s demo module): `--import-memory`,
  `--initial-memory=--max-memory=5177344` (79 pages), `--global-base=0x100000`,
  `--no-entry`.

## Build & run
```bash
bash apps/c/build.sh                          # -> docs/demo-c.wasm (uses `zig cc`)
node apps/verify.mjs docs/demo-c.wasm         # headless ABI check
cd docs && python3 -m http.server 3333
# open http://localhost:3333/sealed.html?demo=demo-c.wasm
```
No system `wasm-ld` needed — `zig cc` bundles lld.
