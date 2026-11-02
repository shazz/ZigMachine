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
| `kestrel_corelib.cpp` | ChipNomad's platform layer (corelib) for the machine: colours get palette indices on first use and are drawn straight into VRAM, the frame's real time of audio to the machine's stream (`kestrel_audio.h`), files over the floppy |
| `kestrel_font8x10.cpp` | the ST 8x8 font in 8x10 cells |
| `patches/corelib_font.cpp.sed` | that font as the only resolution |
| `patches/project_io.cpp.sed` | no C++ exceptions on the cart: a throw logs its message and stops the cart |
| `kestrel_ayumi.cpp` | built instead of upstream's `ayumi.cpp` (same API and chip model): the AY/YM stepped event to event in integers (tone edges, noise and envelope steps; what no channel hears advanced in bulk), each sample the exact average of its chip ticks (a box filter) instead of the cubic interpolator + FIR, a one-pole DC blocker. Any rate works; the cart runs 22.05 kHz (`kestrel_main.cpp`) |
| `patches/ayumi.h.sed` | `kestrel_ayumi.cpp`'s state at the end of `struct ayumi` |
| `patches/ayumi_filters.cpp.sed` | the FIR's double constants made float (the filters still link: `chip_ay.cpp` names them for its quality setting, which no longer changes anything) |
| `run.mjs` | headless runner for experiments |

Keys are ChipNomad's desktop mapping (A = X, B = Z, START = Space, SELECT = Left Shift, arrows).

## Status (2 Nov 2026)

- A fresh project's instruments are type None (silent): a note plays once its instrument has a type (on the
  instrument screen, A held + Right: AY Classic). The gate does exactly that (`ports_headless.mjs chipnomad`).
- KESTREL board (2 Nov, before perf/ports-synth): 11 fps, the song slow: upstream's ayumi cost ~4,900 cycles
  a 44.1 kHz sample (8 substeps, cubic interpolation and a FIR in float a sample) and needed rate >= clock / 64.
  perf/ports-synth: `kestrel_ayumi.cpp` at 22.05 kHz, ~1,000 cycles a sample including ChipNomad's mixer
  (frame_cost: cart 3.65 -> 0.46 Mc a frame playing, est 4.45 -> 1.18 Mc with FRESCO), ~22 % of ZIGGY for
  real time; the feed cap is back to 67 ms (a stall). Same pitch (zero crossings identical to upstream's
  stream), level within 10 % (rms 19.2 vs 21.0: the box filter keeps less of the top octave than the FIR).
  The chip state matches upstream's tick-by-tick model exactly (a 3,000-case native test of random register
  writes against upstream's update_mixer, during development). Software-oscillator instruments (AY2 PWM,
  sync, samples, ChipNomad's timer callback) still step tick by tick, as upstream: they cost more.
- Runs; read-only floppy (projects cannot be saved). A malformed project file stops the cart instead of
  showing an error (no exceptions).
