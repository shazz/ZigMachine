# `apps/rust/` — hello world in Rust

`hello.rs` — the same plasma as `apps/c/`, in `no_std` Rust, proving a Rust cart
drives the sealed `machine-video.wasm`: two imports (`env.memory` +
`hwVideoBase()`), a handful of `#[no_mangle]` exports, 8-bit palette indices into
the shared video region.

## The contract this app implements
- **Imports** (`#[link(wasm_import_module = "env")]`): `memory`, `hwVideoBase()`,
  `consoleLogJS`.
- **Exports** (`#[no_mangle] pub extern "C"`): `boot`, `frame(f32)`,
  `isPlaneEnabled(i)->i32` (required), plus no-op
  `hblDispatch/skipBoot/setShadeMode/pointer/input`.
- **Draw**: palette-index bytes at `hwVideoBase()+OFF_VRAM`; RGBA palette at
  `+OFF_PAL` (**alpha 255 = opaque**). Offsets mirror `machine/sdk/memmap.zig`.
- **Link layout** (must match `build.zig`'s demo module): `--import-memory`,
  `--initial-memory=--max-memory=5177344` (79 pages), `--global-base=0x100000`,
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
