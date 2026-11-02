# pt2-clone on the ZigMachine / KESTREL

[pt2-clone](https://github.com/8bitbubsy/pt2-clone) (Olav "8bitbubsy" Sørensen, BSD-3-Clause) is a
pixel-exact ProTracker 2.3D clone in C on SDL2. Its screen is 320x255, drawn at (40,12) of the 400x280
overscan plane. The cart is `docs/demo-pt2.wasm`, on `docs/demo-pt2.zmd` with two modules
(`RONKEN.MOD`, `HYBRID.MOD`, from `docs/music/`) for its DISK OP to load.

## Licence

`LICENSE` is upstream's (BSD-3-Clause, Olav Sørensen), `LICENSE.miniflac` that of the FLAC sample loader in
upstream's `src/smploaders`. The cart is built from upstream commit `d42d5f100f0a6256ad0c085e5beeaa32cf1e8f63`
(30 Oct 2026), which `../fetch.sh` clones untouched. Ours (MIT, as the repo): every `kestrel_*` file,
`split_main.py`, `patches/*.sed`, `Makefile`, `run.mjs`.

## Build

    apps/ports/fetch.sh                  # once: upstream at its pin, into apps/ports/upstream
    make -C apps/ports/pt2 link          # build/demo-pt2.wasm (byte-identical to docs/ at the pin)
    make -C apps/ports/pt2 install       # copy it to docs/, repack docs/demo-pt2.zmd (tools/mkdisks.sh)
    node apps/ports_headless.mjs pt2     # the gate's check: boot, UI pin, DISK OP loads HYBRID.MOD, PLAY

Every upstream source is mirrored into `build/gen/` and patched there by `patches/<file>.sed` (a patch
must change its file, or the build stops). `make EXTRA=-DKESTREL_AUTOLOAD=RONKEN.MOD link` builds a test
cart that opens a module at boot; the shipped cart is built without it.

## Layout

| file | what |
|---|---|
| `split_main.py` | build step: upstream `main()` -> `pt2_boot()`, its main-loop body -> `pt2_frame()`; fails loudly if upstream's loop changes shape |
| `kestrel_main.c` | the cart's exports: `boot()` = `pt2_boot`, `frame(dt)` = one loop pass a VBL, then the scopes and one VBL of audio |
| `kestrel_sdl.c` | the SDL2 calls pt2 makes that the shared layer does not: the 320x255 ARGB frame buffer onto an 8-bit plane, the audio callback fed to the machine's stream, threads run inline, window/renderer no-ops |
| `kestrel_bmp.c` | the 12 big screen bitmaps decoded on demand into one slot (pt2 decodes all of them at boot: ~1.2 MB) |
| `kestrel_port.h` | force-included: the on-demand bitmap hook |
| `patches/*.sed` | each says why in its header: lazy bitmaps, no scope thread (ticked from `frame()`), a smaller visual sync ring, samples capped at 13 KB with a null buffer to match, pt2 draws its own pointer |
| `run.mjs` | headless runner for experiments: PNGs of the frame, `CLICKS="frame,x,y;..."` in pt2 coordinates |

The shared layer `../kestrel_sdl2` gives the heap, WASI over the floppy (read-only) and the input queue.

## Status (2 Nov 2026)

- Loads modules off the floppy since the bigger cart window (4 MiB at HW 1.12.0, 3 MiB since 1.13.0). pt2
  keeps one fixed pool of 33 sample slots and holds two while a module loads (the old song and the new),
  so samples are capped at 13 KB (13312 bytes, `patches/pt2_config.c.sed`); a longer sample is cut at load.
- ProTracker blocks the mouse for a second after boot (its error pointer from startup): a click in that
  second is ignored.
- Read-only floppy: saving a module or sample fails with pt2's own error.
- KESTREL board: not measured. Paula's BLEP and filters use `double` (soft-float on ZIGGY).
