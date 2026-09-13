# `apps/` — carts / scenes (per language)

**New here?** [`docs/TUTORIAL.md`](../docs/TUTORIAL.md) builds one screen from
scratch, step by step, in Zig, C and Rust (`zig/scenes/tutorial.zig`,
`c/scenes/tutorial.c`, `rust/scenes/tutorial.rs`).

The programs that run on the machine — "cartridges". Each links the HW ABI (and
optionally a lib and the ROM) and compiles to a wasm module the loader boots.
One subfolder per language:

- **`zig/`** — the ZigOS demo: boot screen, the effects menu, and every scene
  (Union intro, cracktro ports, GEM desktop host, music debug, …). Compiles to
  `docs/demo.wasm`.
- **`c/`** — `hello.c`, a plasma proving apps are language-agnostic → `docs/demo-c.wasm`.
- **`rust/`** — `hello.rs`, the same in `no_std` Rust → `docs/demo-rust.wasm`, plus
  one cart per screen in `rust/scenes/` → `docs/demo-rust-<scene>.wasm` (CODEF 490,
  V8's Populous intro, with its SNDH music).

`verify.mjs` is a headless ABI check for the foreign-language apps (instantiates
a wasm the way the loader does, runs `boot()`+frames, asserts it drew & animated).

## How an app reaches the machine
The seal is a **wasm ABI**: an app imports `env.memory` + `hwVideoBase()`, exports
`boot()`/`frame(f32)`/`isPlaneEnabled()`, and writes 8-bit palette indices into
the shared video region. Any language that emits `wasm32-freestanding` and can
import a caller-provided memory can write apps. See [[zigmachine-polyglot-apps]].

## Build & run
```bash
# Zig demo (default):
zig build -Dwasm -Drelease=true          # -> docs/demo.wasm
# C / Rust:
bash apps/c/build.sh                      # -> docs/demo-c.wasm
bash apps/rust/build.sh                   # -> docs/demo-rust.wasm
node apps/verify.mjs                       # headless check of demo-c/demo-rust

cd docs && python3 -m http.server 3333
#   /sealed.html                 -> the Zig demo (menu)
#   /sealed.html?demo=demo-c.wasm    -> the C app
#   /sealed.html?demo=demo-rust.wasm -> the Rust app
```
Hard-reload (Ctrl+Shift+R) after every rebuild ([[zigmachine-workflow-cache]]).
