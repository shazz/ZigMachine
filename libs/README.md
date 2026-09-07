# `libs/` — reusable coder libraries (per language)

Open libraries that sit on top of the HW ABI (`machine/sdk/`) and make writing
apps pleasant. One subfolder per language:

- **`zig/`** — **ZigOS**, the mature Zig library: framebuffers, palettes,
  `printText`, HBL registration, a blitter wrapper, and an `effects/` +
  `players/` (MOD/YM/sample) collection. Apps get it via `@import("zigos")` /
  `@import("players")`.
- **`c/`** — *(placeholder)* a future C-ABI convenience shim, so C apps get
  palette / text / HBL helpers instead of reimplementing them against the raw
  memory map.
- **`rust/`** — *(placeholder)* a future Rust helper crate, same idea.

Layer position: `machine` → **`libs`** → `rom` → `apps`. A lib may use the HW
ABI; it must not depend on a ROM or an app.

## Build
The Zig library is compiled as a named module by the top-level build (there is no
separate lib artifact):
```bash
zig build -Dwasm -Drelease=true
```
See `libs/zig/README.md` for what ZigOS exposes.
