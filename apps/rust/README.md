# `apps/rust/` — hello world in Rust

`hello.rs` — the same plasma as `apps/c/`, in `no_std` Rust, proving a Rust cart
drives the sealed `machine-video.wasm` (8-bit palette indices into the shared
video region) AND calls the Zig ROM chip: `rom.wasm` draws a GEM panel over the
plasma, which `apps/verify.mjs` reads back.

## The contract this app implements
- **Imports** (`#[link(wasm_import_module = "env")]`): `memory`, `hwVideoBase()`,
  `consoleLogJS`, and from the ROM (`rom/sdk/rom.zig`): `guiOpenPlane`,
  `romInstallPalettePlane`, `guiRect`, `guiFrame`, `guiText`.
- **Exports** (`#[no_mangle] pub extern "C"`): `boot`, `frame(f32)`,
  `isPlaneEnabled(i)->i32` (required), plus no-op
  `hblDispatch/skipBoot/setShadeMode/pointer/input`.
- **Draw**: palette-index bytes at `hwVideoBase()+OFF_VRAM`; RGBA palette at
  `+OFF_PAL` (**alpha 255 = opaque**). Offsets mirror `machine/sdk/memmap.zig`.
- **Link layout** (must match `build.zig`'s demo module): `--import-memory`,
  `--initial-memory=--max-memory=7340032` (112 pages), `--global-base=0x100000`,
  `--no-entry`.

## Prerequisite
```bash
rustup target add wasm32-unknown-unknown
```

## Build & run
```bash
bash apps/rust/build.sh                        # -> docs/demo-rust.wasm (bundled rust-lld)
node apps/verify.mjs docs/demo-rust.wasm       # headless ABI check
cd docs && python3 -m http.server 3333
# open http://localhost:3333/sealed.html?demo=demo-rust.wasm
```
No system `wasm-ld` needed — rustc bundles `rust-lld`.
