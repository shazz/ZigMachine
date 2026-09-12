# `rom/` — system software (the reference ROM)

The ZigMachine's built-in OS layer. Today that's **GEM** — a desktop + windowing
toolkit — under `rom/gem/`. Maintained by the ZigMachine authors, but the whole
point of the `machine`/`rom` split is that **a ROM is just a module linked
against the HW ABI**, so anyone can write their own.

## Why this is its own layer
Layering is `machine` → `libs/zig` → **`rom`** → `apps`. The ROM links the HW ABI
(`machine/sdk/`), uses ZigOS helpers (`@import("zigos")`), and apps sit on top of
it (`@import("rom")`). GEM is our **reference ROM** — write your own OS/desktop in
Zig, C, or Rust against `machine/sdk/`, expose your own app-facing ABI, and it
drops into the `rom/<your-os>/` slot.

## Layout
- `rom.zig` — umbrella module (`@import("rom")` → `.gem`, `.gui`).
- `gem/` — the reference GEM ROM: `gem.zig` (desktop), `gui.zig` + `gui/` (widget
  toolkit — window chrome, dialogs, menus), `desktop/` (desktop/icons/prefs),
  `gem_glyphs.zig`, `gem_icons.zig`.

## Build & run
Statically linked into the demo for now (no separate artifact yet), so it builds
with the machine:
```bash
zig build -Dwasm -Drelease=true
cd docs && python3 -m http.server 3333   # sealed.html -> menu -> GEM DESKTOP
```

> **Phase 2** — cut GEM into its own `rom.wasm` (linked to `machine/sdk/`,
> exporting a flat app-facing ABI in `rom/sdk/`), wired by the loader like the
> machine is, so a C or Rust app can call the Zig GEM ROM. **Not started**, and
> that polyglot claim is currently untested — the seam is a Zig API, not a wasm
> ABI. (It is NOT a RAM problem: `gem.Desktop` is 2332 bytes. Ask `hwRamFree()`
> before believing otherwise.) Planned in
> [`docs/PHASE2_ROM_CHIP.md`](../docs/PHASE2_ROM_CHIP.md).
