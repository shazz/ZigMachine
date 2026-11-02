# GrafX2 on the ZigMachine / KESTREL

[GrafX2](https://gitlab.com/GrafX2/grafX2) (the GrafX2 team) is a bitmap paint program in the Deluxe Paint
tradition, in C on SDL2. Its 8-bit screen surface is plane 0's VRAM (320x200, normal mode) and its palette
is palette 0, so nothing is copied to present. The cart is `docs/demo-grafx2.wasm`, on `docs/demo-grafx2.zmd`.

## Licence: GPL version 2

GrafX2 is free software under the GNU General Public License version 2 (`COPYING`, upstream's `LICENSE`;
`COPYRIGHT.txt` lists its contributors and the files under other licences). The cart
`docs/demo-grafx2.wasm` is a work based on it and is distributed under the same licence. Its
**corresponding source** is:

- upstream GrafX2 at commit `678a0f54ea7f3eeebc3fa4135213ea63f45a28bd`
  (<https://gitlab.com/GrafX2/grafX2>), unmodified, which `../fetch.sh` clones;
- exactly the patches in this directory, `patches/main.c.sed` and `patches/setup.h.sed`, applied by the
  `Makefile` to a mirror of upstream's `src/` in `build/gen/`;
- the glue in this directory (`kestrel_main.c`, `kestrel_sdl.c`, `kestrel_stubs.c`, `kestrel_port.h`,
  `include/zlib.h`) and the shared layer `../kestrel_sdl2/` (its `include/`, `src/*.c`);
- `Makefile` (the build, compiler flags and the binaryen 132 `--asyncify` pass) with Zig 0.16.0's
  `zig cc` and binaryen 132.0.0 (npm), which `../fetch.sh` fetches and checks.

Rebuild it, byte for byte, from a checkout of this repository:

    apps/ports/fetch.sh
    make -C apps/ports/grafx2 link        # build/demo-grafx2.wasm == docs/demo-grafx2.wasm
    make -C apps/ports/grafx2 install     # copy it to docs/, repack docs/demo-grafx2.zmd (tools/mkdisks.sh)

The disk carries `data/` (upstream's `share/grafx2`: `gfx2def.ini` as is, and the DPaint skin and font
from `skins/` with the `gfx2.gif` icon re-saved as GIF, as this build has no libpng; GPLv2) and `ownpics/`
(plasma and wave pictures made for this port, PI1 / NEO / GIF). Pictures ripped from other people's work
are never put on it.

## Layout

| file | what |
|---|---|
| `kestrel_main.c` | the cart's exports. GrafX2 blocks in its own loops (every dialog), so it runs under Asyncify as a coroutine: `SDL_Delay` unwinds to `boot()`/`frame()`, the next `frame(dt)` rewinds it |
| `kestrel_sdl.c` | the SDL2 calls GrafX2 makes: the screen surface is plane 0's VRAM, the palette is palette 0, `SDL_Delay` yields the frame |
| `kestrel_stubs.c` | what the cart leaves out: the C64 .PRG loader's 6502 emulator, the mounted-volume list (the floppy is the only drive) |
| `include/zlib.h` | the declarations GrafX2 includes without libpng |
| `patches/main.c.sed` | `main` -> `grafx2_main`, called and resumed by `kestrel_main.c` |
| `patches/setup.h.sed` | the default skin and font as GIF |
| `run.mjs` | headless runner for experiments: PNGs of the frame, `CLICKS="frame,x,y;..."` |

Built without TrueType, Lua, recoil, libpng and libtiff (`DEFS` in the Makefile).

## Status (2 Nov 2026)

- Boots into GrafX2's DPaint skin; its first dialog warns that backups are off (the floppy is read-only).
  Tools, palette, menus and the file selector work; the floppy's PI1 / NEO / GIF pictures load.
- Read-only floppy: saving fails with GrafX2's own error.
- `node apps/ports_headless.mjs grafx2`: boot, UI pin, OK closes the warning, a freehand stroke paints.
