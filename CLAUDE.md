# ZigMachine

A fantasy console written in **Zig**, compiled to `wasm32-freestanding-musl`, rendered to
`<canvas>` in the browser. Ports of oldskool Atari/Amiga cracktro effects run as "channels".

## Quick Reference

- **Stack:** **Zig 0.16.0** → WebAssembly + hand-written JS/HTML front-end (no bundler) + Python asset tools
- **Build:** `./build.sh` — NOT bare `zig build`. It builds, then GATES: RAM windows per module, native tests, disk repack + mount/instantiate, and four headless harnesses. Everything it catches is otherwise SILENT (a cart overrunning its window corrupts the video region; a stale `.zmd` fails to instantiate). Outputs `docs/{machine-video,machine-audio,rom,demo,demo-audio,demo-*}.wasm`.
- **Run:** `./serve.sh` (no-store; refuses a port already serving) → **`/sealed.html`**
- **Pick a scene:** compile-time, edit `apps/zig/floppy.zig` (currently `menu`)
- **Structure (4 areas, each with a README):** `machine/` (sealed HW + `machine/sdk/` headers — authors only) · `rom/` (system software; `rom/gem/` = reference GEM ROM — authors only) · `libs/{zig,c,rust}/` (reusable libs; `zig/` = ZigOS) · `apps/{zig,c,rust}/` (carts/scenes; `zig/` = the demo). Also `docs/` (web root + built wasm), `prototypes/` (gitignored reference material), `legacy/` (pre-seal, retired).
- **APIs:** `docs/HW_API.md` (sealed HW ABI) · `rom/sdk/rom.zig` (the ROM's app-facing ABI — what an app links) · `docs/ZIGOS_API.md` (open library) · `docs/HARDWARE_SPEC.md` (design + status §12)
- **Decisions:** `decisions.md` (ADRs) · `docs/PHASE2_ROM_CHIP.md` (the ROM-chip plan, done through 2.3)

## Status (2026-09-12)

**Five wasm modules share one memory.** Sealed `machine-video.wasm` + `rom.wasm`
+ the running cart on the main thread; sealed `machine-audio.wasm` +
`demo-audio.wasm` on the worklet thread. The loader instantiates
**machine → rom → cart**, each importing only from the ones before it.

✅ **Sealed hardware — video + audio**, memory-mapped ABI in `machine/sdk/`.
HW **1.3.0**: the RAM instructions (`hwRamFree()` and friends) let a cart ASK how
much of its window is left instead of guessing, and there is a second 2 MiB window
above the video region for the ROM.

✅ **GEM is a ROM chip.** Its own `rom.wasm`, its own RAM, exporting a flat ABI
(`rom/sdk/rom.zig`) where only numbers cross — handles, not pointers. The desktop
lives there too; `apps/zig/scenes/gem_desktop.zig` is a shell that forwards frames.
Launching is a **host cart swap**: GEM runs a program off the mounted floppy, the
way TOS does.

✅ **Any language can call GEM — tested, not claimed.** `apps/c/hello.c` draws a
real GEM panel through `guiOpenPlane()`, and `apps/verify.mjs` reads the
framebuffer back to prove the ROM rendered it. The Zig-only entry points
(`guiOpen`, which wants a `*ZigOS`) are not enough on their own; see
`decisions.md`.

✅ **Disks have a recipe.** `tools/mkdisks.sh` repacks every `.zmd` from the built
carts (stale ones only); `apps/disk_check.mjs` mounts each image and instantiates
its cart against the host's real `env`. Both run from `build.sh`.

✅ **Music: SNDH on a real 68000.** A vendored Musashi core in `demo-audio.wasm`
runs a tune's own replay code against the sealed YM, with subtune selection.
`machineAudioReset()` means the machine silences the chip when a program ends.

✅ **Apps are polyglot** — C (`apps/c/`) and Rust (`apps/rust/`) carts run at 60fps.

**Open:** the boot ROM is still linked into every cart (moving it inside
`machine-video.wasm` is an idea, not a plan); `docs/demo-medium_overscan.wasm` is a
stale artifact of a scene excluded from the build; the repo has never been pushed.

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
