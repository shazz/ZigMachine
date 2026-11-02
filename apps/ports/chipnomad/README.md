# ChipNomad on the ZigMachine / KESTREL

[ChipNomad](https://github.com/Megus/chipnomad-tracker) (Megus, MIT) is an LSDJ-style tracker for the AY-3-8910 /
YM2149, in C++17. Its text screen is drawn in the Atari ST's 8x8 system font in 8x10 cells: 40x20 cells =
exactly a 320x200 plane. The cart is `docs/demo-chipnomad.wasm`, on `docs/demo-chipnomad.zmd` (the cart alone:
it starts on an empty project).

## Licence

`LICENSE` is upstream's (MIT, ChipNomad). The cart is built from upstream commit
`e4b10d550fa19e3a00c95689450f0a3f542d5589` (10 Oct 2026), which `../fetch.sh` clones untouched. Ours (MIT, as
the repo): every `kestrel_*` file, `patches/*.sed`, `Makefile`, `run.mjs`.

## Build

    apps/ports/fetch.sh
    make -C apps/ports/chipnomad link         # build/demo-chipnomad.wasm (byte-identical to docs/ at the pin)
    make -C apps/ports/chipnomad install      # copy it to docs/, repack docs/demo-chipnomad.zmd (tools/mkdisks.sh)
    node apps/ports_headless.mjs chipnomad    # the gate's check: boot, UI pin, X puts a chain in the song

Upstream's `version.cpp` shows `__DATE__`; the Makefile pins it to the upstream commit's date so a rebuild
is reproducible.

## Layout

| file | what |
|---|---|
| `kestrel_main.cpp` | the cart's exports: upstream's `main()` up to its main loop runs in `boot()` (after the C++ static constructors, `__wasm_call_ctors`: a cart has no `_start`), one pass of the loop per `frame(dt)` |
| `kestrel_corelib.cpp` | ChipNomad's platform layer (corelib) for the machine: colours get palette indices on first use and are drawn straight into VRAM, one VBL of audio a frame to the machine's stream, files over the floppy |
| `kestrel_font8x10.cpp` | the ST 8x8 font in 8x10 cells |
| `patches/corelib_font.cpp.sed` | that font as the only resolution |
| `patches/project_io.cpp.sed` | no C++ exceptions on the cart: a throw logs its message and stops the cart |
| `run.mjs` | headless runner for experiments |

Keys are ChipNomad's desktop mapping (A = X, B = Z, START = Space, SELECT = Left Shift, arrows).

## Status (2 Nov 2026)

- Runs; read-only floppy (projects cannot be saved). A malformed project file stops the cart instead of
  showing an error (no exceptions).
