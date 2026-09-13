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

> **Phase 2 — steps 2.0–2.3 DONE.** GEM is its own `rom.wasm`, linked against
> `machine/sdk/` like a cart, living in its own RAM window
> (`[ROM_RAM_BASE, ROM_RAM_TOP)`) and exporting the flat app-facing ABI in
> [`sdk/rom.zig`](sdk/rom.zig). The host instantiates machine → rom → app. An APP
> imports the named module `rom_sdk` and **never `rom`** — `.gem`/`.gui` are the
> ROM's internals.
>
> The desktop is a singleton inside `rom.wasm`; `apps/zig/scenes/gem_desktop.zig`
> is a shell, and launching a program is a HOST cart swap (the host calls
> `romReset()` on every swap to reclaim the outgoing program's handles). The
> polyglot claim is tested: `apps/verify.mjs` reads back a GEM panel that
> `rom.wasm` drew for the C app (`apps/c`) and for the Rust app (`apps/rust`).
> Left: step 2.4 (spend the freed RAM). See
> [`docs/PHASE2_ROM_CHIP.md`](../docs/PHASE2_ROM_CHIP.md).

## Layout (chip)
- `rom_main.zig` — **rom.wasm's entry point**: the handle tables + the exported
  flat ABI. This is where the toolkit's state lives, so an app pays nothing for it.
- `sdk/rom.zig` — the app-facing header (`extern` declarations + handle wrappers).
  Change one and change the other in the same commit: nothing checks them against
  each other but the linker.
