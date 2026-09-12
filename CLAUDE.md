# ZigMachine

A fantasy console written in **Zig**, compiled to `wasm32-freestanding-musl`, rendered to
`<canvas>` in the browser. Ports of oldskool Atari/Amiga cracktro effects run as "channels".

## Quick Reference

- **Stack:** **Zig 0.16.0** → WebAssembly + hand-written JS/HTML front-end (no bundler) + Python asset tools
- **Build:** `zig build -Drelease=true -Dwasm` (outputs the sealed `docs/{machine-video,demo,machine-audio,demo-audio}.wasm`)
- **Run:** `cd docs && python3 -m http.server 3333` → **`/sealed.html`** (sealed HW) or `/` (legacy)
- **Pick a scene:** compile-time, edit `apps/zig/floppy.zig` (currently `menu`)
- **Structure (4 areas, each with a README):** `machine/` (sealed HW + `machine/sdk/` headers — authors only) · `rom/` (system software; `rom/gem/` = reference GEM ROM — authors only) · `libs/{zig,c,rust}/` (reusable libs; `zig/` = ZigOS) · `apps/{zig,c,rust}/` (carts/scenes; `zig/` = the demo). Also `docs/` (web root + built wasm), `prototypes/` (gitignored reference material), `legacy/` (pre-seal, retired).
- **APIs:** `docs/HW_API.md` (sealed ABI) · `docs/ZIGOS_API.md` (open library) · `docs/HARDWARE_SPEC.md` (design + status §12)

## Status (2026-08-22)

✅ **Sealed hardware — VIDEO + AUDIO implemented, reorg done, proven in-browser.**
The machine is four builds: sealed `machine-video.wasm` + open `demo.wasm` (main
thread), sealed `machine-audio.wasm` + open `demo-audio.wasm` (worklet thread),
each pair sharing ONE `WebAssembly.Memory` via a memory-mapped ABI
(`machine/sdk/`). The menu runs **unchanged** at ~60fps — open `docs/sealed.html`.

✅ **Repo reorganised (2026-09-06) into four ownership areas:** `machine/` (sealed
HW), `rom/` (system software — GEM), `libs/{zig,c,rust}/`, `apps/{zig,c,rust}/`.
See `docs/HARDWARE_SPEC.md §12`, and each area's `README.md`.

✅ **Apps are polyglot** — the seal is a wasm ABI, not a Zig API. C (`apps/c/`) and
Rust (`apps/rust/`) "hello world" apps run on the sealed machine at 60fps with
zero host changes. Next: cut the ROM into its own `rom.wasm` chip so any language
can call GEM.

✅ **Migrated from Zig 0.10 → 0.16 and building/running again.**

## Hard Rules — project overrides

- **The global "no file over 200 lines" rule does NOT apply to Zig sources here.**
  Zig's unit of encapsulation is the file-as-struct, and this codebase's long
  files are long for a reason: `machine/video.zig` is one faithful render pass
  whose per-pixel border/overscan accounting must not be split, `machine/sdk/*`
  is a single ABI source of truth, and a scene is one coherent program. Splitting
  those to hit a line count buys nothing and risks the sealed pipeline. Judge Zig
  files on cohesion instead — one clear responsibility per file, split when a
  file starts doing two jobs (as `st_replay` already splits state / ui / draw).
  Every other stack in this repo (JS host, Python tools) keeps the 200-line rule.

## Notes for future edits

- This is now **Zig 0.16** source. Install: `~/.local/zig/0.16.0/zig`, symlinked to
  `~/.local/bin/zig` (so `zig` is on PATH).
- The sealed render pipeline (border/raster/plane) lives in `machine/video.zig`; the
  ABI is `machine/sdk/memmap.zig` (video) + `machine/sdk/audio.zig` (audio). Tread carefully.
- **Cross-module imports**: `apps/zig/` code reaches libraries via named modules —
  `@import("zigos")` (ZigOS), `@import("rom")` (GEM), `@import("players")`,
  `@import("hardware")`/`"audio_hw"` (the ABI) — NOT relative paths; see `build.zig`.
  Named modules are path-independent, which is why the reorg barely touched imports.
  Some retired scenes still use pre-reorg relative imports and need migrating when
  selected in `apps/zig/floppy.zig`.
- **Polyglot apps**: C/Rust build via `apps/{c,rust}/build.sh` (bundled `zig cc` /
  `rust-lld`, no system wasm-ld); headless check `node apps/verify.mjs`; run with
  `docs/sealed.html?demo=demo-c.wasm` / `?demo=demo-rust.wasm`.
- Legacy monolithic path (`docs/index.html` + `loader.js` + committed
  `bootloader.wasm`/`audio.wasm`, sources in `legacy/`) is kept for A/B until retired.
